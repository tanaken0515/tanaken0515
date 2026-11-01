# ポッドキャスト自動編集スクリプト

発話者別のwavファイルをミックスし、Logic Proの「オーディオリージョンから無音部分を削除」相当の処理で無音をカットし、
BGMを重ねて mp3 を出力するローカルスクリプトです。

## 前提

- Ruby 4.x（4系の書き方で実装。miseで管理している場合、このディレクトリに `.tool-versions`（`ruby 4.0.1`）を置いてあるので `cd` すれば自動で切り替わります）
- 追加gemなし（標準ライブラリのみ）
- `ffmpeg` / `ffprobe` 9.0.2（`.tool-versions` で固定。miseなら `mise install` で入ります。起動時に存在とバージョンを確認します）
  - ffmpegはメジャーバージョンアップでオプションが削除されることがあるため（例: `-filter_complex_script` は9.0で削除）、
    バージョンを上げるときは `.tool-versions` を書き換え、後述の「エンドツーエンドの動作確認」を流してから使ってください
- 発話者ごとのwavファイルは同時に録音を開始しており、開始位置が揃っていること（スクリプトでは位置合わせを行いません）

## ディレクトリ構成

```
scripts/podcast/auto_edit/
  main.rb                       # CLI本体
  lib/silence_calculator.rb     # 無音区間→削除範囲→残す区間の純粋ロジック
  lib/split_calculator.rb       # --split 時に分割ファイルの間に挟む無音の長さを計算する純粋ロジック
  lib/loudness_calculator.rb    # ラウドネス測定結果の解析と、音量を揃えるゲインを計算する純粋ロジック
  test/*_test.rb
  recordings/{episode_No}/*.wav # 発話者別の入力wav（2〜3ファイル、最大5ファイル）
  bgm/*.mp3(等)                 # ループ再生前提のBGM音源
  output/{episode_No}.mp3       # 出力先
```

## 使い方

```
ruby main.rb EPISODE_NO [options]
```

例（`recordings/257/*.wav` を使う場合）:

```
cd scripts/podcast/auto_edit
ruby main.rb 257                             # BGMは bgm/sunday_ending.mp3
ruby main.rb 257 --bgm 271_long_BPM110.mp3   # 別のBGMを使う場合
# => output/257.mp3 が生成される
```

### オプション（カッコ内はデフォルト値）

| オプション | 説明 |
| --- | --- |
| `--threshold DB` | 無音判定のしきい値dB（-28） |
| `--silence SEC` | 無音とみなす最低秒数（0.8） |
| `--pre-attack SEC` | 無音終了直前に残す秒数（0.3） |
| `--post-release SEC` | 無音開始直後に残す秒数（0.3） |
| `--bgm FILENAME` | `bgm/` 配下のBGMファイル名（sunday_ending.mp3） |
| `--bgm-delay SEC` | BGMだけが流れる秒数。この秒数後に会話が始まる（3.0） |
| `--bgm-volume RATIO` | BGMの音量倍率（0.05） |
| `--bgm-fade SEC` | 会話終了時のBGMフェードアウト秒数。0で無効（10） |
| `--loudnorm-target LUFS` | 発話者ごとの音量を揃える目標ラウドネス(LUFS)。0で無効（-16） |
| `--split FIRST,LAST` | 途中で途切れて2ファイルに分かれた話者の前半・後半のファイル名（後述） |
| `--dry-run` | 実行するffmpegコマンドを表示するだけで実行しない |
| `--detect-only` | 検出した無音区間と削除範囲を一覧表示して終了（しきい値調整用） |

しきい値を調整したいときは、まず `--detect-only` で無音区間の検出結果を確認してから本実行するのがおすすめです。

```
ruby main.rb 257 --detect-only --threshold -30
```

#### `--split`: 収録トラブルで1人の音声が2ファイルに分かれた場合

収録中に1人の音声が途切れて、前半・後半の2ファイルに分かれてしまった場合に使います。

```
ruby main.rb 259 --split 259_tanaken1.wav,259_tanaken2.wav
```

- 前半ファイルの開始は他の話者の開始と、後半ファイルの終了は他の話者（のうち最長のファイル）の終了と揃っている前提です
- 前半と後半の間には、尺の差から計算した長さの無音を挟んで1本のトラックに連結します
  （途切れていた間は他の話者の音声だけになり、誰も話していなければ通常どおり無音カットされます）
- 連結した1本に対してラウドネスを測ってゲインをかけるので、前半・後半で音量がずれることはありません
- 前半+後半の合計が基準の尺より長い場合は、前提が崩れているのでエラーで終了します

#### `--dry-run` の挙動について

`--dry-run` は「無音カット」「BGM合成」という、実際の出力ファイルを生成するffmpegコマンドについては
**実行せず表示のみ**行います。ただし、その2つのコマンドは無音検出の結果（何箇所をどこからどこまで
切り取るか）が分からないと正確な内容を組み立てられないため、その前段の「ミックス」「無音検出」は
（一時ファイルに対して）実際に実行します。一時ファイルはスクリプト終了時に自動的に削除され、
`output/` 配下にファイルが生成されることはありません。

## 処理の流れ

1. `--split` 指定時は、分割された2ファイルを `apad`（間の無音）+ `concat` で1本に連結する。
   その上で、話者ごとのトラック全体の平均ラウドネスを `ebur128` で測定し、目標ラウドネスとの差分だけ
   `volume` で一定のゲインをかけてから（`aformat` で48kHz/stereoに統一）、`amix`（`normalize=0`, `duration=longest`）で
   1本にミックスし、`alimiter` でピークを約 -1.5dBFS に抑える
   （マイクとの距離・声量の違いなどで入力ごとに音量差があっても、事前に手動で音量を揃える必要はありません。
   ゲインは最大 +20dB で頭打ちにします。`--loudnorm-target 0` で音量調整を無効化できます）
   - `loudnorm` を1パスで使うと、冒頭が無音の音声で無音部分のノイズを大きく持ち上げてしまい、
     それが無音カットされずに残ってしまうため、トラック全体に一定のゲインをかける方式にしています
2. ミックス後の音声に対して `silencedetect` で無音区間を検出し、しきい値・無音最低秒数・pre-attack・post-releaseから
   実際にカットする範囲を計算。残す区間を `atrim` + `asetpts` + `concat` で連結
   （無音判定は話者ごとではなく必ずミックス後に行うことで、同期ズレを防いでいます）
3. カット後の音声を `--bgm-delay` 秒だけ `adelay` で遅らせ、ループ音源のBGMを `-stream_loop -1` で繰り返し、
   `volume` で音量を絞ってから `amix duration=first` で重ねる
   （BGMが先に流れ、数秒後に会話が始まる）。`--bgm-fade` が0より大きい場合は、会話が終わった時点を
   開始点として、そこから `--bgm-fade` 秒かけてBGMだけを `afade` でフェードアウトさせる
   （出力全体の長さは 会話終了時刻 + `--bgm-fade` 秒 になる）

## テスト

`lib/` 配下の純粋ロジック（無音区間の計算・分割ファイルの位置計算・ラウドネスのゲイン計算）は
minitestでテストしています。

```
for t in test/*_test.rb; do ruby $t; done
```

## エンドツーエンドの動作確認（サンプル音声の生成）

実際の収録データがなくても、`ffmpeg` の `lavfi`（`sine` / `anullsrc`）でテスト用のwavを生成して動作確認できます。

```bash
cd scripts/podcast/auto_edit
mkdir -p recordings/999

# 発話者1: 3秒発話 → 2秒無音 → 3秒発話（8秒）
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=3" \
       -f lavfi -i "anullsrc=r=44100:cl=mono:d=2" \
       -f lavfi -i "sine=frequency=440:duration=3" \
       -filter_complex "[0][1][2]concat=n=3:v=0:a=1[out]" -map "[out]" \
       recordings/999/speaker1.wav

# 発話者2: サンプルレート/チャンネル数をわざと変えて確認（内部でaformatにより吸収される）
ffmpeg -y -f lavfi -i "sine=frequency=660:duration=3" \
       -f lavfi -i "anullsrc=r=48000:cl=stereo:d=2" \
       -f lavfi -i "sine=frequency=660:duration=3" \
       -filter_complex "[0][1][2]concat=n=3:v=0:a=1[out]" -map "[out]" \
       -ar 48000 -ac 2 recordings/999/speaker2.wav

# BGMは bgm/sunday_ending.mp3 を使う（なければ適当なmp3/wavを bgm/ に置いて --bgm で指定する）
ruby main.rb 999 --detect-only
ruby main.rb 999
# => output/999.mp3 が生成され、再生して確認できる

# 後片付け
rm -rf recordings/999 output/999.mp3
```

`--split` の動作確認は、10秒の基準ファイルと 3秒+2秒 に分かれたファイルで行えます。
`--detect-only` で無音区間がちょうど `3.00 - 8.00` と出れば、後半が末尾に揃って連結されています。

```bash
mkdir -p recordings/998
ffmpeg -y -f lavfi -i "anullsrc=r=44100:cl=stereo:d=10" recordings/998/other.wav
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=3" recordings/998/me1.wav
ffmpeg -y -f lavfi -i "sine=frequency=880:duration=2" recordings/998/me2.wav
ruby main.rb 998 --split me1.wav,me2.wav --detect-only
rm -rf recordings/998
```

## エラー時の挙動

- 収録ディレクトリ・入力ファイル・BGMファイルが存在しない、入力ファイルが0個または6個以上、
  `ffmpeg`/`ffprobe` が見つからない場合は分かりやすいメッセージを表示して終了します
- `ffmpeg` の実行に失敗した場合は stderr の末尾を表示して非0で終了します

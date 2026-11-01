#!/usr/bin/env ruby
# frozen_string_literal: true

# ポッドキャスト収録後編集の自動化スクリプト。
# 発話者別wavをミックス → 無音カット → BGM合成 して mp3 を出力する。
#
# 使い方:
#   ruby main.rb EPISODE_NO [options]
#
# 例:
#   ruby main.rb 257
#   ruby main.rb 257 --bgm 271_long_BPM110.mp3

require "optparse"
require "open3"
require "tmpdir"
require "fileutils"
require "shellwords"

require_relative "lib/silence_calculator"
require_relative "lib/split_calculator"
require_relative "lib/loudness_calculator"

# stdoutとstderrの出力順序がバッファリングでずれないようにする
$stdout.sync = true

SCRIPT_DIR = __dir__
RECORDINGS_DIR = File.join(SCRIPT_DIR, "recordings")
BGM_DIR = File.join(SCRIPT_DIR, "bgm")
OUTPUT_DIR = File.join(SCRIPT_DIR, "output")

# 6個以上はエラーにする（=5個まで許容）
MAX_INPUT_FILES = 5

Options = Struct.new(
  :threshold, :silence, :pre_attack, :post_release,
  :bgm, :bgm_delay, :bgm_volume, :bgm_fade, :loudnorm_target, :split, :dry_run, :detect_only,
  keyword_init: true
)

# ミックスする話者1人分の音声。通常は1ファイルだが、--split 指定時は
# 前半・後半の2ファイルを gap 秒の無音を挟んで連結したものになる。
Track = Data.define(:files, :gap)

def abort_with(message)
  warn "エラー: #{message}"
  exit 1
end

def parse_options(argv)
  options = Options.new(
    threshold: -28.0,
    silence: 0.8,
    pre_attack: 0.3,
    post_release: 0.3,
    bgm: "sunday_ending.mp3",
    bgm_delay: 3.0,
    bgm_volume: 0.05,
    bgm_fade: 10.0,
    loudnorm_target: -16.0,
    split: nil,
    dry_run: false,
    detect_only: false
  )

  parser = OptionParser.new do |opts|
    opts.banner = "使い方: ruby main.rb EPISODE_NO [options]"
    opts.on("--threshold DB", Float, "無音判定のしきい値(dB) (デフォルト: -28)") { |v| options.threshold = v }
    opts.on("--silence SEC", Float, "無音とみなす最低秒数 (デフォルト: 0.8)") { |v| options.silence = v }
    opts.on("--pre-attack SEC", Float, "無音終了直前に残す秒数 (デフォルト: 0.3)") { |v| options.pre_attack = v }
    opts.on("--post-release SEC", Float, "無音開始直後に残す秒数 (デフォルト: 0.3)") { |v| options.post_release = v }
    opts.on("--bgm FILENAME", "bgm/配下のBGMファイル名 (デフォルト: sunday_ending.mp3)") { |v| options.bgm = v }
    opts.on("--bgm-delay SEC", Float, "BGMだけが流れる秒数 (デフォルト: 3.0)") { |v| options.bgm_delay = v }
    opts.on("--bgm-volume RATIO", Float, "BGMの音量倍率 (デフォルト: 0.05)") { |v| options.bgm_volume = v }
    opts.on("--bgm-fade SEC", Float, "会話終了時のBGMフェードアウト秒数、0で無効 (デフォルト: 10)") { |v| options.bgm_fade = v }
    opts.on("--loudnorm-target LUFS", Float, "発話者ごとの音量を揃える目標ラウドネス(LUFS)。0で無効化 (デフォルト: -16)") { |v| options.loudnorm_target = v }
    opts.on("--split FIRST,LAST", Array,
            "途中で途切れて2ファイルに分かれた話者の前半,後半のファイル名。前半は先頭、後半は末尾を他の話者に揃える") do |v|
      options.split = v
    end
    opts.on("--dry-run", "実行するffmpegコマンドを表示するだけで実行しない") { options.dry_run = true }
    opts.on("--detect-only", "検出した無音区間と削除範囲を一覧表示して終了(しきい値調整用)") { options.detect_only = true }
  end

  parser.parse!(argv)
  [options, parser]
end

# 外部コマンドの存在とバージョンを起動時に確認する
def check_external_command!(command)
  stdout, _stderr, status = Open3.capture3(command, "-version")
  abort_with("#{command} の実行に失敗しました") unless status.success?
  puts "#{command}: #{stdout.lines.first&.strip}"
rescue Errno::ENOENT
  abort_with("#{command} が見つかりません。インストールしてPATHを通してください")
end

def probe_duration(path)
  stdout, stderr, status = Open3.capture3(
    "ffprobe", "-v", "error", "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1", path
  )
  abort_with("ffprobeに失敗しました: #{path}\n#{stderr}") unless status.success?
  stdout.strip.to_f
end

def show_ffmpeg_command(args)
  puts "$ ffmpeg #{Shellwords.join(args)}"
end

# ffmpegをコマンド配列で実行する（シェル文字列連結はしない）
def run_ffmpeg!(args, step_name:)
  show_ffmpeg_command(args)
  _stdout, stderr, status = Open3.capture3("ffmpeg", *args)
  unless status.success?
    warn "ffmpegが失敗しました(#{step_name})"
    warn stderr.lines.last(20).join
    exit 1
  end
  stderr
end

AFORMAT = "aformat=sample_rates=48000:channel_layouts=stereo"

# 1トラック分の入力を48kHz/stereoに揃えて [label] に出力するフィルタを組み立てる。
# 2ファイルに分かれたトラックは、前半の後ろに apad で無音を足してから後半と concat する。
# post_filter を指定すると、揃えた後にそのフィルタをかける。
def build_track_chain(track, indexes, label, post_filter = nil)
  tail = ",#{post_filter}" if post_filter

  if indexes.size == 1
    "[#{indexes[0]}:a]#{AFORMAT}#{tail}[#{label}]"
  else
    first, last = indexes
    pad = ",apad=pad_dur=#{track.gap}" if track.gap.positive?
    [
      "[#{first}:a]#{AFORMAT}#{pad}[#{label}_a]",
      "[#{last}:a]#{AFORMAT}[#{label}_b]",
      "[#{label}_a][#{label}_b]concat=n=2:v=0:a=1#{tail}[#{label}]"
    ].join(";")
  end
end

# トラック全体の平均ラウドネスを ebur128 で測定するコマンドを組み立てる。
# 分割トラックは連結した状態で測る（間の無音はEBU R128のゲートで計算から除外される）。
def build_measure_args(track)
  inputs = track.files.flat_map { |f| ["-i", f] }
  chain = build_track_chain(track, track.files.each_index.to_a, "out", "ebur128=framelog=quiet")
  ["-nostats", *inputs, "-filter_complex", chain, "-map", "[out]", "-f", "null", "-"]
end

# 話者ごとの音量を揃えるためのゲイン(dB)をトラックごとに測定して返す。
def measure_gains(tracks, loudnorm_target)
  tracks.map do |track|
    names = track.files.map { |f| File.basename(f) }.join(" + ")
    stderr = run_ffmpeg!(build_measure_args(track), step_name: "ラウドネス測定")
    measured = LoudnessCalculator.parse_integrated(stderr)
    gain = LoudnessCalculator.gain_db(measured, loudnorm_target)
    puts format("ラウドネス: %s = %s → ゲイン %+.2fdB", names, measured ? format("%.1f LUFS", measured) : "測定不可", gain)
    gain
  end
end

# 話者ごとのトラックを1本にミックスする。サンプルレート/チャンネル数のばらつきは
# aformatで48kHz/stereoに揃えてから amix する。
# gains が指定されていれば、amixする前にトラックごとに一定のゲインをかけて音量(ラウドネス)を揃え、
# ミックス後に alimiter でピークを -1.5dBFS 程度に抑える。
# （loudnormの1パス処理は冒頭が無音だとノイズを大きく持ち上げてしまうため使わない）
def build_mix_args(tracks, mixed_path, gains)
  inputs = tracks.flat_map(&:files).flat_map { |f| ["-i", f] }

  input_index = 0
  chains = tracks.each_with_index.map do |track, t|
    indexes = track.files.each_index.map { input_index.tap { input_index += 1 } }
    volume = format("volume=%.2fdB", gains[t]) if gains
    build_track_chain(track, indexes, "a#{t}", volume)
  end
  labels = tracks.each_index.map { |t| "[a#{t}]" }.join
  limiter = ",alimiter=limit=0.84:level=disabled:latency=enabled" if gains
  filter = "#{chains.join(';')};#{labels}amix=inputs=#{tracks.size}:duration=longest:normalize=0#{limiter}[mixed]"

  ["-y", *inputs, "-filter_complex", filter, "-map", "[mixed]", mixed_path]
end

# 入力ファイルを話者ごとのトラックにまとめる。
# --split 指定時は、前半ファイルの開始を他の話者の開始に、後半ファイルの終了を
# 他の話者のうち最長のファイルの終了に揃えるよう、間に挟む無音の長さを計算する。
def build_tracks(input_files, split)
  return input_files.map { |f| Track.new(files: [f], gap: 0.0) } if split.nil?

  abort_with("--split には前半,後半の2ファイルをカンマ区切りで指定してください") unless split.size == 2
  abort_with("--split に同じファイルが指定されています") if split.uniq.size != split.size

  by_name = input_files.to_h { |f| [File.basename(f), f] }
  split_files = split.map do |name|
    by_name.fetch(name) { abort_with("--split で指定したファイルが収録ディレクトリにありません: #{name}") }
  end
  others = input_files - split_files
  abort_with("--split で指定したファイル以外に、位置合わせの基準となる話者のファイルが必要です") if others.empty?

  first_duration, last_duration = split_files.map { |f| probe_duration(f) }
  reference_duration = others.map { |f| probe_duration(f) }.max

  gap = begin
    SplitCalculator.gap_duration(first_duration, last_duration, reference_duration)
  rescue SplitCalculator::InvalidDurationError => e
    abort_with(e.message)
  end
  puts format("分割ファイルの連結: %s(%.2f秒) + 無音(%.2f秒) + %s(%.2f秒) = 基準の尺 %.2f秒",
              split[0], first_duration, gap, split[1], last_duration, reference_duration)

  others.map { |f| Track.new(files: [f], gap: 0.0) } + [Track.new(files: split_files, gap: gap)]
end

def build_silencedetect_args(mixed_path, threshold, silence)
  ["-i", mixed_path, "-af", "silencedetect=noise=#{threshold}dB:d=#{silence}", "-f", "null", "-"]
end

# 残す区間を atrim + asetpts で切り出し、concat で連結するコマンドを組み立てる。
# 区間が多いとコマンドが長くなるため -/filter_complex でファイル渡しにする
# （旧来の -filter_complex_script は ffmpeg 7.0 で非推奨、9.0 で削除された）。
def build_cut_args(mixed_path, keep_ranges, script_path, cut_path)
  lines = keep_ranges.each_with_index.map do |(s, e), i|
    "[0:a]atrim=start=#{s}:end=#{e},asetpts=PTS-STARTPTS[c#{i}]"
  end
  concat_labels = keep_ranges.each_index.map { |i| "[c#{i}]" }.join
  lines << "#{concat_labels}concat=n=#{keep_ranges.size}:v=0:a=1[cut]"
  File.write(script_path, lines.join(";\n"))

  ["-y", "-i", mixed_path, "-/filter_complex", script_path, "-map", "[cut]", cut_path]
end

# BGMを bgm-delay 秒だけ遅らせた会話に重ねる。
# フェードアウトは「会話が終わった時点」を開始点として、そこから bgm-fade 秒かけて行う
# （会話終了ちょうどでフェードが終わるのではなく、会話終了後にBGMだけがフェードアウトしながら流れる）。
# そのため talk 側を apad で bgm-fade 秒分の無音パディングをして、amix duration=first の
# 出力尺が「会話終了 + bgm-fade」までになるようにしている。
def build_bgm_args(cut_path, bgm_path, cut_duration, options, output_path)
  delay_ms = (options.bgm_delay * 1000).round
  talk_end = options.bgm_delay + cut_duration
  fade = [options.bgm_fade, 0].max

  bgm_chain = "[1:a]volume=#{options.bgm_volume}"
  bgm_chain += ",afade=t=out:st=#{talk_end}:d=#{fade}" if fade.positive?
  bgm_chain += "[bgm]"

  talk_chain = "[0:a]adelay=#{delay_ms}|#{delay_ms}"
  talk_chain += ",apad=pad_dur=#{fade}" if fade.positive?
  talk_chain += "[talk]"

  filter = [
    talk_chain,
    bgm_chain,
    "[talk][bgm]amix=inputs=2:duration=first:normalize=0[out]"
  ].join(";")

  [
    "-y", "-i", cut_path, "-stream_loop", "-1", "-i", bgm_path,
    "-filter_complex", filter, "-map", "[out]", "-b:a", "192k", output_path
  ]
end

def print_periods_table(total_duration, periods, options)
  puts "総尺: #{format('%.2f', total_duration)}秒 / 検出された無音区間: #{periods.size}件"
  puts format("%-4s %-18s %-18s", "#", "無音区間(秒)", "削除範囲(秒)")
  periods.each_with_index do |period, i|
    removal = SilenceCalculator.removal_range_for(
      period, total_duration, pre_attack: options.pre_attack, post_release: options.post_release
    )
    removal_str = removal ? format("%.2f - %.2f", *removal) : "(短すぎるため削除しない)"
    puts format("%-4d %-18s %-18s", i + 1, format("%.2f - %.2f", *period), removal_str)
  end
end

def main
  options, parser = parse_options(ARGV)
  episode_no, *extra_args = ARGV

  if episode_no.nil?
    puts parser
    exit 1
  end
  abort_with("不明な引数です: #{extra_args.join(' ')}（BGMは --bgm で指定してください）") unless extra_args.empty?

  check_external_command!("ffmpeg")
  check_external_command!("ffprobe")

  recordings_dir = File.join(RECORDINGS_DIR, episode_no)
  abort_with("収録ディレクトリが見つかりません: #{recordings_dir}") unless Dir.exist?(recordings_dir)

  input_files = Dir.glob(File.join(recordings_dir, "*.wav")).sort
  abort_with("入力ファイルが見つかりません: #{recordings_dir}") if input_files.empty?
  if input_files.size > MAX_INPUT_FILES
    abort_with("入力ファイルが多すぎます(#{input_files.size}個)。#{MAX_INPUT_FILES}個以下にしてください")
  end

  bgm_path = File.join(BGM_DIR, options.bgm)
  abort_with("BGMファイルが見つかりません: #{bgm_path}") unless File.exist?(bgm_path)

  tracks = build_tracks(input_files, options.split)

  FileUtils.mkdir_p(OUTPUT_DIR)
  output_path = File.join(OUTPUT_DIR, "#{episode_no}.mp3")

  Dir.mktmpdir("auto_edit_") do |tmp_dir|
    mixed_path = File.join(tmp_dir, "mixed.wav")
    cut_path = File.join(tmp_dir, "cut.wav")
    script_path = File.join(tmp_dir, "cut_filter.txt")

    # ラウドネス測定・1. ミックス・2. 無音検出は、後続コマンドを正確に組み立てるための解析ステップなので
    #    --dry-run でも実行する（一時ファイルはブロック終了時に自動削除される）。
    gains = measure_gains(tracks, options.loudnorm_target) if options.loudnorm_target.nonzero?

    puts "[1/3] ミックス"
    run_ffmpeg!(build_mix_args(tracks, mixed_path, gains), step_name: "ミックス")

    total_duration = probe_duration(mixed_path)

    puts "[2/3] 無音検出"
    silencedetect_stderr = run_ffmpeg!(
      build_silencedetect_args(mixed_path, options.threshold, options.silence), step_name: "無音検出"
    )

    periods = SilenceCalculator.detect_periods(silencedetect_stderr, total_duration)
    removal = SilenceCalculator.removal_ranges(
      periods, total_duration, pre_attack: options.pre_attack, post_release: options.post_release
    )
    keep = SilenceCalculator.keep_ranges(removal, total_duration)

    if options.detect_only
      print_periods_table(total_duration, periods, options)
      return
    end

    abort_with("無音区間の削除の結果、音声が残りませんでした。しきい値を見直してください") if keep.empty?

    cut_args = build_cut_args(mixed_path, keep, script_path, cut_path)

    if options.dry_run
      puts "[3/3] 無音カット (無音検出の結果に基づく実際のコマンド。dry-runのため実行しません)"
      show_ffmpeg_command(cut_args)
      # dry-runではカットを実行しないため、残す区間の合計から尺を見積もる
      cut_duration = keep.sum { |s, e| e - s }
    else
      puts "[3/3] 無音カット"
      run_ffmpeg!(cut_args, step_name: "無音カット")
      cut_duration = probe_duration(cut_path)
    end

    bgm_args = build_bgm_args(cut_path, bgm_path, cut_duration, options, output_path)

    if options.dry_run
      puts "[BGM合成] (dry-runのため実行しません)"
      show_ffmpeg_command(bgm_args)
      puts "dry-runのため出力ファイルは生成していません"
    else
      puts "[BGM合成]"
      run_ffmpeg!(bgm_args, step_name: "BGM合成")
      puts "出力しました: #{output_path}"
    end
  end
end

main if $PROGRAM_NAME == __FILE__

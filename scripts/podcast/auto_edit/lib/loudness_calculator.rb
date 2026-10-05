# frozen_string_literal: true

# 話者ごとの音量を揃えるための純粋なロジック集。
# 副作用（ファイルI/Oやコマンド実行）は一切持たない。
#
# loudnorm を1パスで使うと、冒頭が無音の音声で無音（ノイズ）を大きく持ち上げてしまうため、
# 事前に ebur128 でトラック全体の平均ラウドネスを測り、その差分だけ一定のゲインをかける方式にしている。
module LoudnessCalculator
  module_function

  # ほぼ無音のトラックでノイズを持ち上げすぎないよう、ゲインの上限を設ける
  MAX_GAIN_DB = 20.0

  # ebur128フィルタのstderr出力から、Summaryの Integrated loudness (LUFS) を取り出す。
  # 無音で測定できなかった場合（-inf や見つからない場合）は nil を返す。
  def parse_integrated(ffmpeg_stderr)
    m = ffmpeg_stderr.scan(/Integrated loudness:\s*\n\s*I:\s*(-?[\d.]+|-inf)\s*LUFS/).last
    return nil if m.nil? || m[0] == "-inf"

    m[0].to_f
  end

  # 測定したラウドネスを目標値に揃えるためのゲイン(dB)を返す。
  # 測定できなかった場合は 0、上げすぎる場合は MAX_GAIN_DB で頭打ちにする。
  def gain_db(measured, target, max_gain: MAX_GAIN_DB)
    return 0.0 if measured.nil?

    [target - measured, max_gain].min
  end
end

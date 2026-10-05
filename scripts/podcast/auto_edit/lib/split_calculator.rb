# frozen_string_literal: true

# 収録トラブルで1人の話者の音声が前半・後半の2ファイルに分かれてしまった場合に、
# 2ファイルの間に挟む無音の長さを計算する純粋なロジック。
# 副作用（ファイルI/Oやコマンド実行）は一切持たない。
#
# 前提:
#   - 前半ファイルの開始は、他の話者のファイルの開始と揃っている
#   - 後半ファイルの終了は、他の話者のファイルの終了と揃っている
module SplitCalculator
  module_function

  # 計算誤差（ファイル尺の端数など）として許容する秒数。
  # 隙間がこの範囲でマイナスになった場合は 0 として扱う。
  TOLERANCE = 0.05

  class InvalidDurationError < StandardError; end

  # 前半・後半ファイルの間に挟む無音の秒数を返す。
  # reference_duration は末尾を揃える基準となる尺（他の話者のファイルのうち最長のもの）。
  # 前半+後半の合計が基準より明らかに長い場合は、前提が崩れているので例外にする。
  def gap_duration(first_duration, last_duration, reference_duration)
    gap = reference_duration - first_duration - last_duration

    if gap < -TOLERANCE
      raise InvalidDurationError,
            format("分割ファイルの合計(%.2f秒)が基準の尺(%.2f秒)より長いため、位置を決められません",
                   first_duration + last_duration, reference_duration)
    end

    [gap, 0.0].max
  end
end

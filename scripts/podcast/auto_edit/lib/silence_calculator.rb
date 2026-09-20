# frozen_string_literal: true

# ffmpegのsilencedetectフィルタの出力を解析し、
# 無音区間 → 削除範囲 → 残す区間、を計算する純粋なロジック集。
# 副作用（ファイルI/Oやコマンド実行）は一切持たない。
module SilenceCalculator
  module_function

  # silencedetectのstderr出力を解析して無音区間 [start, end] の配列にする。
  # 末尾まで無音が続き silence_end が出てこない場合は total_duration を end とする。
  def detect_periods(ffmpeg_stderr, total_duration)
    periods = []
    current_start = nil

    ffmpeg_stderr.each_line do |line|
      if (m = line.match(/silence_start:\s*(-?[\d.]+)/))
        current_start = m[1].to_f
      elsif (m = line.match(/silence_end:\s*(-?[\d.]+)/)) && current_start
        periods << [current_start, m[1].to_f]
        current_start = nil
      end
    end

    periods << [current_start, total_duration] if current_start

    periods
  end

  # 1つの無音区間から、実際に削除する範囲を計算する。
  # 基本は [start + post_release, end - pre_attack]。
  # 先頭無音は [0, end - pre_attack]、末尾無音は [start + post_release, total_duration]。
  # 計算後に start >= end になる場合（無音が短くマージンで食い潰される場合）は削除せず nil を返す。
  def removal_range_for(period, total_duration, pre_attack:, post_release:)
    p_start, p_end = period
    leading = p_start <= 0.0
    trailing = p_end >= total_duration - 0.001

    start = leading ? 0.0 : p_start + post_release
    finish = trailing ? total_duration : p_end - pre_attack

    return nil unless start < finish

    [start, finish]
  end

  # 無音区間の配列から、実際に削除する範囲の配列を計算する（短すぎる区間は除外される）。
  def removal_ranges(periods, total_duration, pre_attack:, post_release:)
    periods.filter_map { |period| removal_range_for(period, total_duration, pre_attack: pre_attack, post_release: post_release) }
  end

  # 削除範囲の補集合として、残す区間（音声として残す部分）を計算する。
  def keep_ranges(removal_ranges, total_duration)
    sorted = removal_ranges.sort_by(&:first)
    result = []
    cursor = 0.0

    sorted.each do |r_start, r_end|
      result << [cursor, r_start] if cursor < r_start
      cursor = [cursor, r_end].max
    end

    result << [cursor, total_duration] if cursor < total_duration
    result
  end
end

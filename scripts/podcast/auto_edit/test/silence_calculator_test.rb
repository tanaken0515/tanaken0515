# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/silence_calculator"

class SilenceCalculatorTest < Minitest::Test
  def test_detect_periods_parses_middle_and_trailing_silence
    stderr = <<~LOG
      [silencedetect @ 0x0] silence_start: 1
      [silencedetect @ 0x0] silence_end: 2 | silence_duration: 1
      [silencedetect @ 0x0] silence_start: 9
    LOG

    periods = SilenceCalculator.detect_periods(stderr, 10.0)

    assert_equal [[1.0, 2.0], [9.0, 10.0]], periods
  end

  def test_removal_range_for_leading_silence
    range = SilenceCalculator.removal_range_for([0.0, 2.0], 10.0, pre_attack: 0.2, post_release: 0.2)

    assert_equal [0.0, 1.8], range
  end

  def test_removal_range_for_trailing_silence
    range = SilenceCalculator.removal_range_for([8.0, 10.0], 10.0, pre_attack: 0.2, post_release: 0.2)

    assert_equal [8.2, 10.0], range
  end

  def test_removal_range_for_middle_silence
    range = SilenceCalculator.removal_range_for([4.0, 6.0], 10.0, pre_attack: 0.2, post_release: 0.2)

    assert_equal [4.2, 5.8], range
  end

  def test_removal_range_for_too_short_after_margins_is_not_removed
    # 無音長0.8秒に対しpre_attack/post_releaseが0.5秒ずつだと start >= end になり削除されない
    range = SilenceCalculator.removal_range_for([4.0, 4.8], 10.0, pre_attack: 0.5, post_release: 0.5)

    assert_nil range
  end

  def test_removal_ranges_filters_out_too_short_periods
    periods = [[4.0, 4.8], [6.0, 8.0]]

    ranges = SilenceCalculator.removal_ranges(periods, 10.0, pre_attack: 0.5, post_release: 0.5)

    assert_equal [[6.5, 7.5]], ranges
  end

  def test_keep_ranges_is_complement_of_removal_ranges
    removal = [[1.8, 8.2]]

    keep = SilenceCalculator.keep_ranges(removal, 10.0)

    assert_equal [[0.0, 1.8], [8.2, 10.0]], keep
  end

  def test_keep_ranges_with_multiple_removals
    removal = [[6.5, 7.5], [2.0, 3.0]]

    keep = SilenceCalculator.keep_ranges(removal, 10.0)

    assert_equal [[0.0, 2.0], [3.0, 6.5], [7.5, 10.0]], keep
  end

  def test_keep_ranges_with_no_removal
    keep = SilenceCalculator.keep_ranges([], 10.0)

    assert_equal [[0.0, 10.0]], keep
  end
end

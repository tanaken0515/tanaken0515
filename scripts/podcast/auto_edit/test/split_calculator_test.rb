# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/split_calculator"

class SplitCalculatorTest < Minitest::Test
  def test_gap_duration_fills_missing_middle
    gap = SplitCalculator.gap_duration(1236.18, 257.16, 1518.479002)

    assert_in_delta 25.139002, gap, 1e-6
  end

  def test_gap_duration_is_zero_when_files_are_contiguous
    assert_in_delta 0.0, SplitCalculator.gap_duration(6.0, 4.0, 10.0), 1e-9
  end

  def test_gap_duration_clamps_small_negative_error_to_zero
    assert_in_delta 0.0, SplitCalculator.gap_duration(6.0, 4.01, 10.0), 1e-9
  end

  def test_gap_duration_raises_when_files_are_longer_than_reference
    assert_raises(SplitCalculator::InvalidDurationError) do
      SplitCalculator.gap_duration(6.0, 5.0, 10.0)
    end
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/loudness_calculator"

class LoudnessCalculatorTest < Minitest::Test
  def test_parse_integrated_reads_summary
    stderr = <<~LOG
      [Parsed_ebur128_0 @ 0x0] t: 1.2   TARGET:-23 LUFS    M: -25.0 S:-120.7     I: -25.0 LUFS       LRA:   0.0 LU
      [Parsed_ebur128_0 @ 0x0] Summary:

        Integrated loudness:
          I:         -20.1 LUFS
          Threshold: -30.4 LUFS
    LOG

    assert_in_delta(-20.1, LoudnessCalculator.parse_integrated(stderr), 1e-9)
  end

  def test_parse_integrated_returns_nil_for_silence
    stderr = <<~LOG
      Integrated loudness:
        I:         -inf LUFS
    LOG

    assert_nil LoudnessCalculator.parse_integrated(stderr)
  end

  def test_parse_integrated_returns_nil_when_missing
    assert_nil LoudnessCalculator.parse_integrated("no summary")
  end

  def test_gain_db_is_difference_from_target
    assert_in_delta 4.12, LoudnessCalculator.gain_db(-20.12, -16.0), 1e-9
    assert_in_delta(-2.0, LoudnessCalculator.gain_db(-14.0, -16.0), 1e-9)
  end

  def test_gain_db_is_capped
    assert_in_delta 20.0, LoudnessCalculator.gain_db(-70.0, -16.0), 1e-9
  end

  def test_gain_db_is_zero_when_not_measured
    assert_in_delta 0.0, LoudnessCalculator.gain_db(nil, -16.0), 1e-9
  end
end

# frozen_string_literal: true

require_relative 'helper'

class TestTimeline < Minitest::Test
  def setup
    @timeline = Timeline.new(5)
  end

  def test_new_should_be_empty
    assert_equal 0, @timeline.size
  end

  def test_should_not_grow_to_more_than_size
    (1..10).each do |i|
      @timeline.push(i)
    end

    assert_equal [6, 7, 8, 9, 10], @timeline
  end

  def test_clear_should_clear_array
    @timeline << 1
    assert_equal [1], @timeline
    assert_empty @timeline.clear
  end

  # def test_benchmark
  #   require 'benchmark'
  #
  #   count = 1_000_000
  #
  #   t = Timeline.new(10)
  #
  #   Benchmark.bmbm do |x|
  #     x.report("go") { count.times { t.push(5) } }
  #   end
  # end
end

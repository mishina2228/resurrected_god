# frozen_string_literal: true

require_relative 'helper'

class TestConditionsTries < Minitest::Test
  # valid?

  def test_valid_should_return_false_if_times_not_set
    c = Conditions::Tries.new
    c.watch = stub(name: 'foo')
    refute c.valid?
  end
end

class TestConditionsTries < Minitest::Test
  def setup
    @c = Conditions::Tries.new
    @c.times = 3
    @c.prepare
  end

  # prepare

  def test_prepare_should_create_timeline
    assert_equal 3, @c.instance_variable_get(:@timeline).instance_variable_get(:@max_size)
  end

  # test

  def test_test_should_return_true_if_called_three_times_within_one_second
    refute @c.test
    refute @c.test
    assert @c.test
  end

  # reset

  def test_test_should_return_false_on_fourth_call_if_called_three_times_within_one_second
    3.times { @c.test }
    @c.reset
    refute @c.test
  end
end

class TestConditionsTriesWithin < Minitest::Test
  def setup
    @c = Conditions::Tries.new
    @c.times = 3
    @c.within = 1.seconds
    @c.prepare
  end

  # test

  def test_test_should_return_true_if_called_three_times_within_one_second
    refute @c.test
    refute @c.test
    assert @c.test
  end

  def test_test_should_return_false_if_called_three_times_within_two_seconds
    refute @c.test
    refute @c.test
    assert sleep(1.1)
    refute @c.test
  end
end

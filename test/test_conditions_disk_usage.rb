# frozen_string_literal: true

require_relative 'helper'

class TestConditionsDiskUsage < Minitest::Test
  # valid?

  def test_valid_should_return_false_if_no_above_given
    c = Conditions::DiskUsage.new
    c.mount_point = '/'
    c.watch = stub(name: 'foo')
    refute c.valid?
  end

  def test_valid_should_return_false_if_no_mount_point_given
    c = Conditions::DiskUsage.new
    c.above = 90
    c.watch = stub(name: 'foo')
    refute c.valid?
  end

  def test_valid_should_return_true_if_required_options_all_set
    c = Conditions::DiskUsage.new
    c.above = 90
    c.mount_point = '/'
    c.watch = stub(name: 'foo')

    assert c.valid?
  end

  # test

  def test_test_should_return_true_if_above_limit
    c = Conditions::DiskUsage.new
    c.above = 90
    c.mount_point = '/'

    c.expects(:`).returns('91')

    assert c.test
  end

  def test_test_should_return_false_if_below_limit
    c = Conditions::DiskUsage.new
    c.above = 90
    c.mount_point = '/'

    c.expects(:`).returns('90')

    refute c.test
  end
end

# frozen_string_literal: true

require_relative 'helper'

class TestRegistry < Minitest::Test
  def setup
    God.registry.reset
  end

  def test_add
    foo = God::Process.new
    foo.name = 'foo'
    God.registry.add(foo)
    assert_equal 1, God.registry.size
    assert_equal foo, God.registry['foo']
  end
end

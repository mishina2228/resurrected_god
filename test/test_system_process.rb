# frozen_string_literal: true

require_relative 'helper'

class TestSystemProcess < Minitest::Test
  def setup
    pid = Process.pid
    @process = System::Process.new(pid)
  end

  def test_exists_should_return_true_for_running_process
    assert @process.exists?
  end

  def test_exists_should_return_false_for_non_existent_process
    refute System::Process.new(9999999).exists?
  end

  def test_memory
    assert_kind_of Integer, @process.memory
    assert @process.memory > 0
  end

  def test_percent_memory
    assert_kind_of Float, @process.percent_memory
  end

  def test_percent_cpu
    assert_kind_of Float, @process.percent_cpu
  end
end

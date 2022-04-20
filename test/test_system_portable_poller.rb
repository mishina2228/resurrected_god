# frozen_string_literal: true

require_relative 'helper'

class TestSystemPortablePoller < Minitest::Test
  def setup
    pid = Process.pid
    @process = System::PortablePoller.new(pid)
  end
end

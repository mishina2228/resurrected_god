# frozen_string_literal: true

require_relative 'helper'
require 'open3'

class TestGemspec < Minitest::Test
  def teardown
    FileUtils.rm(Dir.glob('resurrected_god*.gem'))
  end

  def test_gem_build_has_no_warnings
    _o, e, s = Bundler.with_original_env { Open3.capture3('gem build resurrected_god.gemspec') }
    refute_includes e, 'WARNING'
    assert s.success?
  end
end

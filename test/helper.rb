# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter 'test/'
end
if ENV['CI']
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require 'English'
require 'minitest/autorun'
require 'mocha/minitest'
require 'mocha/api'

# Use this flag to actually load all of the god infrastructure
$load_god = true

require_relative '../lib/god/sys_logger'
require_relative '../lib/god'

God::EventHandler.load

include God

module God
  module Conditions
    class FakeCondition < Condition
      def test
        true
      end
    end

    class FakePollCondition < PollCondition
      def test
        true
      end
    end

    class FakeEventCondition < EventCondition
      def register
      end

      def deregister
      end
    end
  end

  module Behaviors
    class FakeBehavior < Behavior
      def before_start
        'foo'
      end

      def after_start
        'bar'
      end
    end
  end

  module Contacts
    class FakeContact < Contact
      # Dummy Contact used by `God.contact(:fake_contact)`
    end

    class InvalidContact
      # Dummy Contact used by `God.contact(:invalid_contact)`
    end
  end

  def self.reset
    self.watches = nil
    self.groups = nil
    self.server = nil
    self.inited = nil
    self.host = nil
    self.port = nil
    self.pid_file_directory = nil
    registry.reset
  end
end

def silence_warnings
  old_verbose = $VERBOSE
  $VERBOSE = nil
  yield
ensure
  $VERBOSE = old_verbose
end

LOG.instance_variable_set(:@io, StringIO.new)

def output_logs
  io = LOG.instance_variable_get(:@io)
  LOG.instance_variable_set(:@io, $stderr)
  yield
ensure
  LOG.instance_variable_set(:@io, io)
end

module Minitest
  module Assertions
    def assert_abort(&block)
      assert_raises SystemExit, &block
    end

    def assert_nothing_raised
      yield
    end
  end
end

# This allows you to be a good OOP citizen and honor encapsulation, but
# still make calls to private methods (for testing) by doing
#
#   obj.bypass.private_thingie(arg1, arg2)
#
# Which is easier on the eye than
#
#   obj.send(:private_thingie, arg1, arg2)
#
class Object
  class Bypass
    instance_methods.each do |m|
      undef_method m unless /^(__|object_id)/.match?(m)
    end

    def initialize(ref)
      @ref = ref
    end

    def method_missing(sym, *args)
      @ref.__send__(sym, *args)
    end
  end

  def bypass
    Bypass.new(self)
  end
end

# Make sure we return valid exit codes
if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby'
  module Kernel
    alias __at_exit at_exit
    def at_exit(&block)
      __at_exit do
        exit_status = $ERROR_INFO.status if $ERROR_INFO.is_a?(SystemExit)
        block.call
        exit exit_status if exit_status
      end
    end
  end
end

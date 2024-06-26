# frozen_string_literal: true

module God
  module Configurable
    # Override this method in your Configurable (optional)
    #
    # Called once after the Configurable has been sent to the block and attributes have been
    # set. Do any post-processing on attributes here
    def prepare
    end

    def reset
    end

    # Override this method in your Configurable (optional)
    #
    # Called once during evaluation of the config file. Return true if valid, false otherwise
    #
    # A convenience method 'complain' is available that will print out a message and return false,
    # making it easy to report multiple validation errors:
    #
    #   def valid?
    #     valid = true
    #     valid &= complain("You must specify the 'pid_file' attribute for :memory_usage") if self.pid_file.nil?
    #     valid &= complain("You must specify the 'above' attribute for :memory_usage") if self.above.nil?
    #     valid
    #   end
    def valid?
      true
    end

    def base_name
      @base_name ||= self.class.name.split('::').last
    end

    def friendly_name
      base_name
    end

    # configurable - Should respond to :watch and :friendly_name
    def self.complain(text, configurable = nil)
      watch = configurable.watch rescue nil
      msg = ''
      msg += "#{watch.name}: " if watch
      msg += text
      msg += " for #{configurable.friendly_name}" if configurable
      applog(watch, :error, msg)
      false
    end

    def complain(text, configurable = nil)
      Configurable.complain(text, configurable)
    end
  end
end

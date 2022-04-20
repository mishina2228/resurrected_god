# frozen_string_literal: true

module God
  module Conditions
    # Condition Symbol :file_touched
    # Type: Poll
    #
    # Trigger when a specified file is touched.
    #
    # Parameters
    #   Required
    #     +path+ is the path to the file to watch.
    #
    # Examples
    #
    # Trigger if 'tmp/restart.txt' file is touched (from a Watch):
    #
    #   on.condition(:file_touched) do |c|
    #     c.path = 'tmp/restart.txt'
    #   end
    #
    class FileTouched < PollCondition
      attr_accessor :path

      def initialize
        super
        self.path = nil
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'path' must be specified", self) if path.nil?
        valid
      end

      def test
        if File.exist?(path)
          (Time.now - File.mtime(path)) <= interval
        else
          false
        end
      end
    end
  end
end

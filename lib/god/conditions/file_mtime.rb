# frozen_string_literal: true

module God
  module Conditions
    class FileMtime < PollCondition
      attr_accessor :path, :max_age

      def initialize
        super
        self.path = nil
        self.max_age = nil
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'path' must be specified", self) if path.nil?
        valid &= complain("Attribute 'max_age' must be specified", self) if max_age.nil?
        valid
      end

      def test
        (Time.now - File.mtime(path)) > max_age
      end
    end
  end
end

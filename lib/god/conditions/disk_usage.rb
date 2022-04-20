# frozen_string_literal: true

module God
  module Conditions
    class DiskUsage < PollCondition
      attr_accessor :above, :mount_point

      def initialize
        super
        self.above = nil
        self.mount_point = nil
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'mount_point' must be specified", self) if mount_point.nil?
        valid &= complain("Attribute 'above' must be specified", self) if above.nil?
        valid
      end

      def test
        self.info = []
        usage = `df -P | grep -i " #{mount_point}$" | awk '{print $5}' | sed 's/%//'`
        if usage.to_i > above
          self.info = 'disk space out of bounds'
          true
        else
          false
        end
      end
    end
  end
end

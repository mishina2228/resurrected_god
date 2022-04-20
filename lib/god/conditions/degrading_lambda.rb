# frozen_string_literal: true

module God
  module Conditions
    # This condition degrades its interval by a factor of two for 3 tries before failing
    class DegradingLambda < PollCondition
      attr_accessor :lambda

      def initialize
        super
        @tries = 0
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'lambda' must be specified", self) if self.lambda.nil?
        valid
      end

      def test
        puts "Calling test. Interval at #{interval}"
        @original_interval ||= interval
        if pass?
          @tries = 0
          self.interval = @original_interval
        else
          if @tries == 2
            self.info = 'lambda condition was satisfied'
            return true
          end
          self.interval = interval / 2.0
          @tries += 1
        end

        self.info = 'lambda condition was not satisfied'
        false
      end

      private

      def pass?
        Timeout.timeout(@interval) do
          self.lambda.call
        end
      rescue Timeout::Error
        false
      end
    end
  end
end

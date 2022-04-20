# frozen_string_literal: true

module God
  module Conditions
    class Tries < PollCondition
      attr_accessor :times, :within

      def prepare
        @timeline = Timeline.new(times)
      end

      def reset
        @timeline.clear
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'times' must be specified", self) if times.nil?
        valid
      end

      def test
        @timeline << Time.now

        consensus = (@timeline.size == times)
        duration = within.nil? || (@timeline.last - @timeline.first) < within

        history = if within
                    "[#{@timeline.size}/#{times} within #{(@timeline.last - @timeline.first).to_i}s]"
                  else
                    "[#{@timeline.size}/#{times}]"
                  end

        if consensus && duration
          self.info = "tries exceeded #{history}"
          true
        else
          self.info = "tries within bounds #{history}"
          false
        end
      end
    end
  end
end

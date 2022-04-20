# frozen_string_literal: true

module God
  module Conditions
    # Condition Symbol :memory_usage
    # Type: Poll
    #
    # Trigger when the resident memory of a process is above a specified limit.
    #
    # Parameters
    #   Required
    #     +pid_file+ is the pid file of the process in question. Automatically
    #                populated for Watches.
    #     +above+ is the amount of resident memory (in kilobytes) above which
    #             the condition should trigger. You can also use the sugar
    #             methods #kilobytes, #megabytes, and #gigabytes to clarify
    #             this amount (see examples).
    #
    # Examples
    #
    # Trigger if the process is using more than 100 megabytes of resident
    # memory (from a Watch):
    #
    #   on.condition(:memory_usage) do |c|
    #     c.above = 100.megabytes
    #   end
    #
    # Non-Watch Tasks must specify a PID file:
    #
    #   on.condition(:memory_usage) do |c|
    #     c.above = 100.megabytes
    #     c.pid_file = "/var/run/mongrel.3000.pid"
    #   end
    class MemoryUsage < PollCondition
      attr_accessor :above, :times, :pid_file

      def initialize
        super
        self.above = nil
        self.times = [1, 1]
      end

      def prepare
        self.times = [times, times] if times.is_a?(Integer)

        @timeline = Timeline.new(times[1])
      end

      def reset
        @timeline.clear
      end

      def pid
        pid_file ? File.read(pid_file).strip.to_i : watch.pid
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'pid_file' must be specified", self) if pid_file.nil? && watch.pid_file.nil?
        valid &= complain("Attribute 'above' must be specified", self) if above.nil?
        valid
      end

      def test
        process = System::Process.new(pid)
        @timeline.push(process.memory)
        self.info = []

        history = @timeline.map { |x| "#{x > above ? '*' : ''}#{x}kb" }.join(', ')

        if @timeline.count { |x| x > above } >= times.first
          self.info = "memory out of bounds [#{history}]"
          true
        else
          false
        end
      end
    end
  end
end

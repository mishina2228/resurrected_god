# frozen_string_literal: true

module God
  module Behaviors
    class NotifyWhenFlapping < Behavior
      attr_accessor :failures, # number of failures
                    :seconds, # number of seconds
                    :notifier # class to notify with

      def initialize
        super
        @startup_times = []
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'failures' must be specified", self) unless failures
        valid &= complain("Attribute 'seconds' must be specified", self) unless seconds
        valid &= complain("Attribute 'notifier' must be specified", self) unless notifier

        # Must take one arg or variable args
        unless notifier.respond_to?(:notify) && [1, -1].include?(notifier.method(:notify).arity)
          valid &= complain("The 'notifier' must have a method 'notify' which takes 1 or variable args", self)
        end

        valid
      end

      def before_start
        now = Time.now.to_i
        @startup_times << now
        check_for_flapping(now)
      end

      def before_restart
        now = Time.now.to_i
        @startup_times << now
        check_for_flapping(now)
      end

      private

      def check_for_flapping(now)
        @startup_times.select! { |time| time >= now - seconds }
        return if @startup_times.length < failures

        notifier.notify("#{watch.name} has called start/restart #{@startup_times.length} times in #{seconds} seconds")
      end
    end
  end
end

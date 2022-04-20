# frozen_string_literal: true

module God
  module Conditions
    # Condition Symbol :flapping
    # Type: Trigger
    #
    # Trigger when a Task transitions to or from a state or states a given number
    # of times within a given period.
    #
    # Parameters
    #   Required
    #     +times+ is the number of times that the Task must transition before
    #             triggering.
    #     +within+ is the number of seconds within which the Task must transition
    #              the specified number of times before triggering. You may use
    #              the sugar methods #seconds, #minutes, #hours, #days to clarify
    #              your code (see examples).
    #     --one or both of--
    #     +from_state+ is the state (as a Symbol) from which the transition must occur.
    #     +to_state+ is the state (as a Symbol) to which the transition must occur.
    #
    #   Optional:
    #     +retry_in+ is the number of seconds after which to re-monitor the Task after
    #                it has been disabled by the condition.
    #     +retry_times+ is the number of times after which to permanently unmonitor
    #                   the Task.
    #     +retry_within+ is the number of seconds within which
    #
    # Examples
    #
    # Trigger if
    class Flapping < TriggerCondition
      attr_accessor :times,
                    :within,
                    :from_state,
                    :to_state,
                    :retry_in,
                    :retry_times,
                    :retry_within

      def initialize
        super
        self.info = 'process is flapping'
      end

      def prepare
        @timeline = Timeline.new(times)
        @retry_timeline = Timeline.new(retry_times)
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'times' must be specified", self) if times.nil?
        valid &= complain("Attribute 'within' must be specified", self) if within.nil?
        valid &= complain("Attributes 'from_state', 'to_state', or both must be specified", self) if from_state.nil? && to_state.nil?
        valid
      end

      def process(event, payload)
        return if event != :state_change

        event_from_state, event_to_state = *payload

        from_state_match = !from_state || Array(from_state).include?(event_from_state)
        to_state_match = !to_state || Array(to_state).include?(event_to_state)

        if from_state_match && to_state_match
          @timeline << Time.now

          consensus = (@timeline.size == times)
          duration = (@timeline.last - @timeline.first) < within

          if consensus && duration
            @timeline.clear
            trigger
            retry_mechanism
          end
        end
      rescue => e
        puts e.message
        puts e.backtrace.join("\n")
      end

      private

      def retry_mechanism
        return unless retry_in

        @retry_timeline << Time.now

        consensus = (@retry_timeline.size == retry_times)
        duration = (@retry_timeline.last - @retry_timeline.first) < retry_within

        if consensus && duration
          # give up
          Thread.new do
            sleep 1

            # log
            msg = "#{watch.name} giving up"
            applog(watch, :info, msg)
          end
        else
          # try again later
          Thread.new do
            sleep 1

            # log
            msg = "#{watch.name} auto-reenable monitoring in #{retry_in} seconds"
            applog(watch, :info, msg)

            sleep retry_in

            # log
            msg = "#{watch.name} auto-reenabling monitoring"
            applog(watch, :info, msg)

            watch.monitor if watch.state == :unmonitored
          end
        end
      end
    end
  end
end

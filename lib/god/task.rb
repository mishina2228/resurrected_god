# frozen_string_literal: true

module God
  class Task
    # Public: Gets/Sets the String name of the task.
    attr_accessor :name

    # Public: Gets/Sets the Numeric default interval to be used between poll
    # events.
    attr_accessor :interval

    # Public: Gets/Sets the String group name of the task.
    attr_accessor :group

    # Public: Gets/Sets the Array of Symbol valid states for the state machine.
    attr_accessor :valid_states

    # Public: Gets/Sets the Symbol initial state of the state machine.
    attr_accessor :initial_state

    # Gets/Sets the Driver for this task.
    attr_accessor :driver

    # Public: Sets whether the task should autostart when god starts. Defaults
    # to true (enabled).
    attr_writer :autostart

    # Returns true if autostart is enabled, false if not.
    def autostart?
      @autostart
    end

    # api
    attr_accessor :state, :behaviors, :metrics, :directory

    def initialize
      @autostart = true

      # initial state is unmonitored
      self.state = :unmonitored

      # the list of behaviors
      self.behaviors = []

      # the list of conditions for each action
      self.metrics = { nil => [], :unmonitored => [], :stop => [] }

      # the condition -> metric lookup
      self.directory = {}

      # driver
      self.driver = Driver.new(self)
    end

    # Initialize the metrics to an empty state.
    #
    # Returns nothing.
    def prepare
      valid_states.each do |state|
        metrics[state] ||= []
      end
    end

    # Verify that the minimum set of configuration requirements has been met.
    #
    # Returns true if valid, false if not.
    def valid?
      valid = true

      # A name must be specified.
      if name.nil?
        valid = false
        applog(self, :error, 'No name String was specified.')
      end

      # Valid states must be specified.
      if valid_states.nil?
        valid = false
        applog(self, :error, 'No valid_states Array or Symbols was specified.')
      end

      # An initial state must be specified.
      if initial_state.nil?
        valid = false
        applog(self, :error, 'No initial_state Symbol was specified.')
      end

      valid
    end

    ###########################################################################
    #
    # Advanced mode
    #
    ###########################################################################

    # Convert the given input into canonical hash form which looks like:
    #
    # { true => :state } or { true => :state, false => :otherstate }
    #
    # to - The Symbol or Hash destination.
    #
    # Returns the canonical Hash.
    def canonical_hash_form(to)
      to.instance_of?(Symbol) ? { true => to } : to
    end

    # Public: Define a transition handler which consists of a set of conditions
    #
    # start_states - The Symbol or Array of Symbols start state(s).
    # end_states   - The Symbol or Hash end states.
    #
    # Yields the Metric for this transition.
    #
    # Returns nothing.
    def transition(start_states, end_states)
      # Convert end_states into canonical hash form.
      canonical_end_states = canonical_hash_form(end_states)

      Array(start_states).each do |start_state|
        # Validate start state.
        unless valid_states.include?(start_state)
          abort "Invalid state :#{start_state}. Must be one of the symbols #{valid_states.map { |x| ":#{x}" }.join(', ')}"
        end

        # Create a new metric to hold the task, end states, and conditions.
        m = Metric.new(self, canonical_end_states)

        if block_given?
          # Let the config file define some conditions on the metric.
          yield(m)
        else
          # Add an :always condition if no block was given.
          m.condition(:always) do |c|
            c.what = true
          end
        end

        # Populate the condition -> metric directory.
        m.conditions.each do |c|
          directory[c] = m
        end

        # Record the metric.
        metrics[start_state] ||= []
        metrics[start_state] << m
      end
    end

    # Public: Define a lifecycle handler. Conditions that belong to a
    # lifecycle are active as long as the process is being monitored.
    #
    # Returns nothing.
    def lifecycle
      # Create a new metric to hold the task and conditions.
      m = Metric.new(self)

      # Let the config file define some conditions on the metric.
      yield(m)

      # Populate the condition -> metric directory.
      m.conditions.each do |c|
        directory[c] = m
      end

      # Record the metric.
      metrics[nil] << m
    end

    ###########################################################################
    #
    # Lifecycle
    #
    ###########################################################################

    # Enable monitoring.
    #
    # Returns nothing.
    def monitor
      move(initial_state)
    end

    # Disable monitoring.
    #
    # Returns nothing.
    def unmonitor
      move(:unmonitored)
    end

    # Move to the given state.
    #
    # to_state - The Symbol representing the state to move to.
    #
    # Returns this Task.
    def move(to_state)
      if driver.in_driver_context?
        # Called from within Driver. Record original info.
        orig_to_state = to_state
        from_state = state

        # Log.
        msg = "#{name} move '#{from_state}' to '#{to_state}'"
        applog(self, :info, msg)

        # Cleanup from current state.
        driver.clear_events
        metrics[from_state].each(&:disable)
        metrics[nil].each(&:disable) if to_state == :unmonitored

        # Perform action.
        action(to_state)

        # Enable simple mode.
        to_state = :up if [:start, :restart].include?(to_state) && metrics[to_state].empty?

        # Move to new state.
        metrics[to_state].each(&:enable)

        # If no from state, enable lifecycle metric.
        metrics[nil].each(&:enable) if from_state == :unmonitored

        # Set state.
        self.state = to_state

        # Broadcast to interested TriggerConditions.
        Trigger.broadcast(self, :state_change, [from_state, orig_to_state])

        # Log.
        msg = "#{name} moved '#{from_state}' to '#{to_state}'"
        applog(self, :info, msg)
      else
        # Called from outside Driver. Send an async message to Driver.
        driver.message(:move, [to_state])
      end

      self
    end

    # Notify the Driver that an EventCondition has triggered.
    #
    # condition - The Condition.
    #
    # Returns nothing.
    def trigger(condition)
      driver.message(:handle_event, [condition])
    end

    def signal(sig)
      # noop
    end

    ###########################################################################
    #
    # Actions
    #
    ###########################################################################

    def method_missing(sym, *args)
      super unless /=$/.match?(sym.to_s)

      base = sym.to_s.chop.intern

      super unless valid_states.include?(base)

      self.class.send(:attr_accessor, base)
      send(sym, *args)
    end

    # Perform the given action.
    #
    # action - The Symbol action.
    # condition - The Condition.
    #
    # Returns this Task.
    def action(action, condition = nil)
      if !driver.in_driver_context?
        # Called from outside Driver. Send an async message to Driver.
        driver.message(:action, [action, condition])
      elsif respond_to?(action)
        # Called from within Driver.
        command = send(action)

        case command
        when String
          msg = "#{name} #{action}: #{command}"
          applog(self, :info, msg)

          system(command)
        when Proc
          msg = "#{name} #{action}: lambda"
          applog(self, :info, msg)

          command.call
        else
          raise NotImplementedError
        end
      end
    end

    ###########################################################################
    #
    # Events
    #
    ###########################################################################

    def attach(condition)
      case condition
      when PollCondition
        driver.schedule(condition, 0)
      when EventCondition, TriggerCondition
        condition.register
      end
    end

    def detach(condition)
      case condition
      when PollCondition
        condition.reset
      when EventCondition, TriggerCondition
        condition.deregister
      end
    end

    ###########################################################################
    #
    # Registration
    #
    ###########################################################################

    def register!
      # override if necessary
    end

    def unregister!
      driver.shutdown
    end

    ###########################################################################
    #
    # Handlers
    #
    ###########################################################################

    # Evaluate and handle the given poll condition. Handles logging
    # notifications, and moving to the new state if necessary.
    #
    # condition - The Condition to handle.
    #
    # Returns nothing.
    def handle_poll(condition)
      # Lookup metric.
      metric = directory[condition]

      # Run the test.
      begin
        result = condition.test
      rescue Object => e
        cname = condition.class.to_s.split('::').last
        message = format("Unhandled exception in %{cname} condition - (%{class}): %{message}\n%{backtrace}",
                         cname: cname, class: e.class, message: e.message, backtrace: e.backtrace.join("\n"))
        applog(self, :error, message)
        result = false
      end

      # Log.
      messages = log_line(self, metric, condition, result)

      # Notify.
      notify(condition, messages.last) if result && condition.notify

      # After-condition.
      condition.after

      # Get the destination.
      dest =
        if result && condition.transition
          # Condition override.
          condition.transition
        else
          # Regular.
          metric.destination && metric.destination[result]
        end

      # Transition or reschedule.
      if dest
        # Transition.
        begin
          move(dest)
        rescue EventRegistrationFailedError
          msg = "#{name} Event registration failed, moving back to previous state"
          applog(self, :info, msg)

          dest = state
          retry
        end
      else
        # Reschedule.
        driver.schedule(condition)
      end
    end

    # Asynchronously evaluate and handle the given event condition. Handles
    # logging notifications, and moving to the new state if necessary.
    #
    # condition - The Condition to handle.
    #
    # Returns nothing.
    def handle_event(condition)
      # Lookup metric.
      metric = directory[condition]

      # Log.
      messages = log_line(self, metric, condition, true)

      # Notify.
      notify(condition, messages.last) if condition.notify

      # Get the destination.
      dest = condition.transition || (metric.destination && metric.destination[true])

      return unless dest

      move(dest)
    end

    # Determine whether a trigger happened.
    #
    # metric - The Metric.
    # result - The Boolean result from the condition's test.
    #
    # Returns Boolean
    def trigger?(metric, result)
      metric.destination && metric.destination[result]
    end

    # Log info about the condition and return the list of messages logged.
    #
    # watch     - The Watch.
    # metric    - The Metric.
    # condition - The Condition.
    # result    - The Boolean result of the condition test evaluation.
    #
    # Returns the Array of String messages.
    def log_line(watch, metric, condition, result)
      status =
        if trigger?(metric, result)
          '[trigger]'
        else
          '[ok]'
        end

      messages = []

      # Log info if available.
      if condition.info
        Array(condition.info).each do |condition_info|
          messages << "#{watch.name} #{status} #{condition_info} (#{condition.base_name})"
          applog(watch, :info, messages.last)
        end
      else
        messages << "#{watch.name} #{status} (#{condition.base_name})"
        applog(watch, :info, messages.last)
      end

      # Log.
      debug_message = "#{watch.name} #{condition.base_name} [#{result}] #{dest_desc(metric, condition)}"
      applog(watch, :debug, debug_message)

      messages
    end

    # Format the destination specification for use in debug logging.
    #
    # metric    - The Metric.
    # condition - The Condition.
    #
    # Returns the formatted String.
    def dest_desc(metric, condition)
      if condition.transition
        { true => condition.transition }.inspect
      elsif metric.destination
        metric.destination.inspect
      else
        'none'
      end
    end

    # Notify all recipients of the given condition with the specified message.
    #
    # condition - The Condition.
    # message   - The String message to send.
    #
    # Returns nothing.
    def notify(condition, message)
      spec = Contact.normalize(condition.notify)
      unmatched = []

      # Resolve contacts.
      resolved_contacts =
        spec[:contacts].inject([]) do |acc, contact_name_or_group|
          cons = Array(God.contacts[contact_name_or_group] || God.contact_groups[contact_name_or_group])
          unmatched << contact_name_or_group if cons.empty?
          acc += cons
          acc
        end

      # Warn about unmatched contacts.
      unless unmatched.empty?
        msg = "#{condition.watch.name} no matching contacts for '#{unmatched.join(', ')}'"
        applog(condition.watch, :warn, msg)
      end

      # Notify each contact.
      resolved_contacts.each do |c|
        host = `hostname`.chomp rescue 'none'
        begin
          c.notify(message, Time.now, spec[:priority], spec[:category], host)
          msg = "#{condition.watch.name} #{c.info || "notification sent for contact: #{c.name}"} (#{c.base_name})"
          applog(condition.watch, :info, msg)
        rescue Exception => e
          applog(condition.watch, :error, "#{e.message} #{e.backtrace}")
          msg = "#{condition.watch.name} Failed to deliver notification for contact: #{c.name} (#{c.base_name})"
          applog(condition.watch, :error, msg)
        end
      end
    end
  end
end

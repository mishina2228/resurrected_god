# frozen_string_literal: true

# Bail out before loading anything unless this flag is set.
#
# We are doing this to guard against bundler autoloading because there is
# no value in loading god in most processes.
if $load_god

  # core
  require 'stringio'
  require 'fileutils'

  # internal requires
  require 'god/errors'
  require 'god/simple_logger'
  require 'god/logger'
  require 'god/sugar'

  require 'god/system/process'
  require 'god/system/portable_poller'
  require 'god/system/slash_proc_poller'

  require 'god/timeline'
  require 'god/configurable'

  require 'god/task'

  require 'god/behavior'
  require 'god/behaviors/clean_pid_file'
  require 'god/behaviors/clean_unix_socket'
  require 'god/behaviors/notify_when_flapping'

  require 'god/condition'
  require 'god/conditions/process_running'
  require 'god/conditions/process_exits'
  require 'god/conditions/tries'
  require 'god/conditions/memory_usage'
  require 'god/conditions/cpu_usage'
  require 'god/conditions/always'
  require 'god/conditions/lambda'
  require 'god/conditions/degrading_lambda'
  require 'god/conditions/flapping'
  require 'god/conditions/http_response_code'
  require 'god/conditions/disk_usage'
  require 'god/conditions/complex'
  require 'god/conditions/file_mtime'
  require 'god/conditions/file_touched'
  require 'god/conditions/socket_responding'

  require 'god/socket'
  require 'god/driver'

  require 'god/metric'
  require 'god/watch'

  require 'god/trigger'
  require 'god/event_handler'
  require 'god/registry'
  require 'god/process'

  require 'god/version'
  require 'god/cli/version'
  require 'god/cli/command'

  CONTACT_DEPS = {
    webhook: ['json'],
    slack: ['json'],
    airbrake: ['airbrake']
  }.freeze
  CONTACT_LOAD_SUCCESS = {}

  def load_contact(name)
    require "god/contacts/#{name}"
    CONTACT_LOAD_SUCCESS[name] = true
  rescue LoadError
    CONTACT_LOAD_SUCCESS[name] = false
  end

  require 'god/contact'
  load_contact(:email)
  load_contact(:webhook)
  load_contact(:airbrake)
  load_contact(:slack)

  $LOAD_PATH.unshift File.join(File.dirname(__FILE__), *%w[.. ext god])

  # App wide logging system
  LOG = God::Logger.new

  def applog(watch, level, text)
    LOG.log(watch, level, text)
  end

  # The $run global determines whether god should be started when the
  # program would normally end. This should be set to true if when god
  # should be started (e.g. `god -c <config file>`) and false otherwise
  # (e.g. `god status`)
  $run ||= nil

  GOD_ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  # Return the binding of god's root level
  def root_binding
    binding
  end

  module Kernel
    alias abort_orig abort

    def abort(text = nil)
      $run = false
      applog(nil, :error, text) if text
      exit(1)
    end

    alias exit_orig exit

    def exit(code = 0)
      $run = false
      exit_orig(code)
    end
  end

  class Module
    def safe_attr_accessor(*args)
      args.each do |arg|
        define_method(:"#{arg}=") do |other|
          abort "God.#{arg} must be set before any Tasks are defined" if !running && inited

          if running && inited
            applog(nil, :warn, "God.#{arg} can't be set while god is running")
            return
          end

          instance_variable_set(:"@#{arg}", other)
        end

        define_method(arg) do
          instance_variable_get(:"@#{arg}")
        end
      end
    end
  end

  module God
    # The Integer number of lines of backlog to keep for the logger.
    LOG_BUFFER_SIZE_DEFAULT = 100

    # An Array of directory paths to be used as the default PID file directory.
    # This list will be searched in order and the first one that has write
    # permissions will be used.
    PID_FILE_DIRECTORY_DEFAULTS = ['/var/run/god', '~/.god/pids'].freeze

    # The default Integer port number for the DRb communications channel.
    DRB_PORT_DEFAULT = 17165

    # The default Array of String IPs that will allow DRb communication access.
    DRB_ALLOW_DEFAULT = ['127.0.0.1'].freeze

    # The default Symbol log level.
    LOG_LEVEL_DEFAULT = :info

    # The default Integer number of seconds to wait for god to terminate when
    # issued the quit command.
    TERMINATE_TIMEOUT_DEFAULT = 10

    # The default Integer number of seconds to wait for a process to terminate.
    STOP_TIMEOUT_DEFAULT = 10

    # The default String signal to send for the stop command.
    STOP_SIGNAL_DEFAULT = 'TERM'

    class << self
      # user configurable
      safe_attr_accessor :pid,
                         :host,
                         :port,
                         :allow,
                         :log_buffer_size,
                         :pid_file_directory,
                         :log_file,
                         :log_level,
                         :use_events,
                         :terminate_timeout,
                         :socket_user,
                         :socket_group,
                         :socket_perms

      # internal
      attr_accessor :inited,
                    :running,
                    :pending_watches,
                    :pending_watch_states,
                    :server,
                    :watches,
                    :groups,
                    :contacts,
                    :contact_groups,
                    :main
    end

    # Initialize class instance variables.
    self.pid = nil
    self.host = nil
    self.port = nil
    self.allow = nil
    self.log_buffer_size = nil
    self.pid_file_directory = nil
    self.log_level = nil
    self.terminate_timeout = nil
    self.socket_user = nil
    self.socket_group = nil
    self.socket_perms = 0755

    # Initialize internal data.
    #
    # Returns nothing.
    def self.internal_init
      # Only do this once.
      return if inited

      # Variable init.
      self.watches = {}
      self.groups = {}
      self.pending_watches = []
      self.pending_watch_states = {}
      self.contacts = {}
      self.contact_groups = {}

      # Set defaults.
      self.log_buffer_size ||= LOG_BUFFER_SIZE_DEFAULT
      self.port ||= DRB_PORT_DEFAULT
      self.allow ||= DRB_ALLOW_DEFAULT
      self.log_level ||= LOG_LEVEL_DEFAULT
      self.terminate_timeout ||= TERMINATE_TIMEOUT_DEFAULT

      # Additional setup.
      setup

      # Log level.
      log_level_map = { debug: Logger::DEBUG,
                        info: Logger::INFO,
                        warn: Logger::WARN,
                        error: Logger::ERROR,
                        fatal: Logger::FATAL }
      LOG.level = log_level_map[self.log_level]

      # Init has been executed.
      self.inited = true

      # Not yet running.
      self.running = false
    end

    # Instantiate a new, empty Watch object and pass it to the mandatory block.
    # The attributes of the watch will be set by the configuration file. Aborts
    # on duplicate watch name, invalid watch, or conflicting group name.
    #
    # Returns nothing.
    def self.watch(&block)
      task(Watch, &block)
    end

    # Instantiate a new, empty Task object and yield it to the mandatory block.
    # The attributes of the task will be set by the configuration file. Aborts
    # on duplicate task name, invalid task, or conflicting group name.
    #
    # Returns nothing.
    def self.task(klass = Task)
      # Ensure internal init has run.
      internal_init

      t = klass.new
      yield(t)

      # Do the post-configuration.
      t.prepare

      # If running, completely remove the watch (if necessary) to prepare for
      # the reload
      existing_watch = watches[t.name]
      if running && existing_watch
        pending_watch_states[existing_watch.name] = existing_watch.state
        unwatch(existing_watch)
      end

      # Ensure the new watch has a unique name.
      abort "Task name '#{t.name}' already used for a Task or Group" if watches[t.name] || groups[t.name]

      # Ensure watch is internally valid.
      t.valid? || abort("Task '#{t.name}' is not valid (see above)")

      # Add to list of watches.
      watches[t.name] = t

      # Add to pending watches.
      pending_watches << t

      # Add to group if specified.
      if t.group
        # Ensure group name hasn't been used for a watch already.
        abort "Group name '#{t.group}' already used for a Task" if watches[t.group]

        groups[t.group] ||= []
        groups[t.group] << t
      end

      # Register watch.
      t.register!

      # Log.
      if running && existing_watch
        applog(t, :info, "#{t.name} Reloaded config")
      elsif running
        applog(t, :info, "#{t.name} Loaded config")
      end
    end

    # Unmonitor and remove the given watch from god.
    #
    # watch - The Watch to remove.
    #
    # Returns nothing.
    def self.unwatch(watch)
      # Unmonitor.
      watch.unmonitor unless watch.state == :unmonitored

      # Unregister.
      watch.unregister!

      # Remove from watches.
      watches.delete(watch.name)

      # Remove from groups.
      groups[watch.group].delete(watch) if watch.group

      applog(watch, :info, "#{watch.name} unwatched")
    end

    # Instantiate a new Contact of the given kind and send it to the block.
    # Then prepare, validate, and record the Contact. Aborts on invalid kind,
    # duplicate contact name, invalid contact, or conflicting group name.
    #
    # kind - The Symbol contact class specifier.
    #
    # Returns nothing.
    def self.contact(kind)
      # Ensure internal init has run.
      internal_init

      # Verify contact has been loaded.
      if CONTACT_LOAD_SUCCESS[kind] == false
        applog(nil, :error, "A required dependency for the #{kind} contact is unavailable.")
        applog(nil, :error, 'Run the following commands to install the dependencies:')
        CONTACT_DEPS[kind].each do |d|
          applog(nil, :error, "  [sudo] gem install #{d}")
        end
        abort
      end

      # Create the contact.
      begin
        c = Contact.generate(kind)
      rescue NoSuchContactError => e
        abort e.message
      end

      # Send to block so config can set attributes.
      yield(c) if block_given?

      # Call prepare on the contact.
      c.prepare

      # Remove existing contacts of same name.
      existing_contact = contacts[c.name]
      uncontact(existing_contact) if running && existing_contact

      # Warn and noop if the contact has been defined before.
      if contacts[c.name] || contact_groups[c.name]
        applog(nil, :warn, "Contact name '#{c.name}' already used for a Contact or Contact Group")
        return
      end

      # Abort if the Contact is invalid, the Contact will have printed out its
      # own error messages by now.
      abort 'Exiting on invalid contact' unless Contact.valid?(c) && c.valid?

      # Add to list of contacts.
      contacts[c.name] = c

      # Add to contact group if specified.
      return unless c.group

      # Ensure group name hasn't been used for a contact already.
      abort "Contact Group name '#{c.group}' already used for a Contact" if contacts[c.group]

      contact_groups[c.group] ||= []
      contact_groups[c.group] << c
    end

    # Remove the given contact from god.
    #
    # contact - The Contact to remove.
    #
    # Returns nothing.
    def self.uncontact(contact)
      contacts.delete(contact.name)
      return unless contact.group

      contact_groups[contact.group].delete(contact)
    end

    def self.watches_by_name(name)
      case name
      when '', nil then watches.values.dup
      else Array(watches[name] || groups[name]).dup
      end
    end

    # Control the lifecycle of the given task(s).
    #
    # name    - The String name of a task/group. If empty, invokes command for all tasks.
    # command - The String command to run. Valid commands are:
    #           "start", "monitor", "restart", "stop", "unmonitor", "remove".
    #
    # Returns an Array of String task names affected by the command.
    def self.control(name, command)
      # Get the list of items.
      items = watches_by_name(name)

      jobs = []

      # Do the command.
      case command
      when 'start', 'monitor'
        items.each { |w| jobs << Thread.new { w.monitor if w.state != :up } }
      when 'restart'
        items.each { |w| jobs << Thread.new { w.move(:restart) } }
      when 'stop'
        items.each do |w|
          jobs << Thread.new do
            w.action(:stop)
            w.unmonitor if w.state != :unmonitored
          end
        end
      when 'unmonitor'
        items.each { |w| jobs << Thread.new { w.unmonitor if w.state != :unmonitored } }
      when 'remove'
        items.each { |w| unwatch(w) }
      else
        raise InvalidCommandError
      end

      jobs.each(&:join)

      items.map(&:name)
    end

    # Unmonitor and stop all tasks.
    #
    # Returns true on success, false if all tasks could not be stopped within 10
    # seconds
    def self.stop_all
      watches.sort.each do |(_name, w)|
        Thread.new do
          w.action(:stop)
          w.unmonitor if w.state != :unmonitored
        end
      end

      terminate_timeout.times do
        return true if watches.none? { |_name, w| w.alive? }

        sleep 1
      end

      false
    end

    # Force the termination of god.
    # * Clean up pid file if one exists
    # * Stop DRb service
    # * Hard exit using exit!
    #
    # Never returns because the process will no longer exist!
    def self.terminate
      FileUtils.rm_f(pid) if pid
      server&.stop
      exit!(0)
    end

    # Gather the status of each task.
    #
    # Examples
    #
    #   God.status
    #   # => { 'mongrel' => :up, 'nginx' => :up }
    #
    # Returns a Hash where the key is the String task name and the value is the
    #   Symbol status.
    def self.status
      info = {}
      watches.map do |name, w|
        info[name] = { state: w.state, group: w.group }
      end
      info
    end

    # Send a signal to each task.
    #
    # name   - The String name of the task or group.
    # signal - The String or integer signal to send. e.g. 'HUP', 9.
    #
    # Returns an Array of String names of the tasks affected.
    def self.signal(name, signal)
      items = watches_by_name(name)
      jobs = items.map { |w| Thread.new { w.signal(signal) } }
      jobs.each(&:join)
      items.map(&:name)
    end

    # Log lines for the given task since the specified time.
    #
    # watch_name - The String name of the task (may be abbreviated).
    # since      - The Time since which to report log lines.
    #
    # Raises God::NoSuchWatchError if no tasks matched.
    # Returns the String of newline separated log lines.
    def self.running_log(watch_name, since)
      matches = pattern_match(watch_name, watches.keys)

      raise NoSuchWatchError unless matches.first

      LOG.watch_log_since(matches.first, since)
    end

    # Load a config file into a running god instance. Rescues any exceptions
    # that the config may raise and reports these back to the caller.
    #
    # code     - The String config file contents.
    # filename - The filename of the config file.
    # action   - The optional String command specifying how to deal with
    #            existing watches. Valid options are: 'stop', 'remove' or
    #            'leave' (default).
    #
    # Returns a three-tuple Array [loaded_names, errors, unloaded_names] where:
    #         loaded_names   - The Array of String task names that were loaded.
    #         errors         - The String of error messages produced during the
    #                          load phase. Will be a blank String if no errors
    #                          were encountered.
    #         unloaded_names - The Array of String task names that were unloaded
    #                          from the system (if 'remove' or 'stop' was
    #                          specified as the action).
    def self.running_load(code, filename, action = nil)
      error_message = +''
      loaded_watches = []
      unloaded_watches = []
      jobs = []

      begin
        LOG.start_capture

        Gem.clear_paths
        eval(code, root_binding, filename) # rubocop:disable Security/Eval
        pending_watches.each do |w|
          if (previous_state = pending_watch_states[w.name])
            w.monitor unless previous_state == :unmonitored
          elsif w.autostart?
            w.monitor
          end
        end
        loaded_watches = pending_watches.map(&:name)
        pending_watches.clear
        pending_watch_states.clear

        watches.each do |name, watch|
          next if loaded_watches.include?(name)

          case action
          when 'stop'
            jobs << Thread.new(watch) do |w|
              w.action(:stop)
              unwatch(w)
            end
            unloaded_watches << name
          when 'remove'
            jobs << Thread.new(watch) { |w| unwatch(w) }
            unloaded_watches << name
          when 'leave', '', nil
            # Do nothing
          else
            raise InvalidCommandError, "Unknown action: #{action}"
          end
        end

        # Make sure we quit capturing when we're done.
        LOG.finish_capture
      rescue Exception => e
        # Don't ever let running_load take down god.
        error_message << LOG.finish_capture

        unless e.instance_of?(SystemExit)
          error_message << e.message << "\n"
          error_message << e.backtrace.join("\n")
        end
      end

      jobs.each(&:join)

      [loaded_watches, error_message, unloaded_watches]
    end

    # Load the given file(s) according to the given glob.
    #
    # glob - The glob-enabled String path to load.
    #
    # Returns nothing.
    def self.load(glob)
      Dir[glob].each do |f|
        Kernel.load f
      end
    end

    # Setup pid file directory and log system.
    #
    # Returns nothing.
    def self.setup
      if pid_file_directory
        dir = File.expand_path(pid_file_directory)
        # Pid file dir was specified, ensure it is created and writable.
        unless File.exist?(dir)
          begin
            FileUtils.mkdir_p(dir)
          rescue Errno::EACCES => e # rubocop:disable Metrics/BlockNesting
            abort "Failed to create pid file directory: #{e.message}"
          end
        end
        abort "The pid file directory (#{dir}) is not writable by #{Etc.getlogin}" unless File.writable?(dir)

        self.pid_file_directory = dir
      else
        # No pid file dir specified, try defaults.
        PID_FILE_DIRECTORY_DEFAULTS.each do |idir|
          dir = File.expand_path(idir)
          begin
            FileUtils.mkdir_p(dir)
            if File.writable?(dir)
              self.pid_file_directory = dir
              break
            end
          rescue Errno::EACCES
            # Ignore errors on directory creation failure here.
          end
        end

        unless pid_file_directory
          dirs = PID_FILE_DIRECTORY_DEFAULTS.map { |x| File.expand_path(x) }
          abort "No pid file directory exists, could be created, or is writable at any of #{dirs.join(', ')}"
        end
      end

      if God::Logger.syslog
        LOG.info('Syslog enabled.')
      else
        LOG.info('Syslog disabled.')
      end

      applog(nil, :info, "Using pid file directory: #{pid_file_directory}")
    end

    # Initialize and startup the machinery that makes god work.
    #
    # Returns nothing.
    def self.start
      internal_init

      # Instantiate server.
      self.server = Socket.new(self.port, socket_user, socket_group, socket_perms)

      # Start monitoring any watches set to autostart.
      watches.each_value { |w| w.monitor if w.autostart? }

      # Clear pending watches.
      pending_watches.clear

      # Mark as running.
      self.running = true

      # Don't exit.
      self.main =
        Thread.new do
          loop do
            sleep 60
          end
        end
    end

    # Prevent god from exiting.
    #
    # Returns nothing.
    def self.join
      main&.join
    end

    # Returns the version String.
    def self.version
      God::VERSION
    end

    # To be called on program exit to start god.
    #
    # Returns nothing.
    def self.at_exit
      start
      join
    end

    # private

    # Match a shortened pattern against a list of String candidates.
    # The pattern is expanded into a regular expression by
    # inserting .* between each character.
    #
    # pattern - The String containing the abbreviation.
    # list    - The Array of Strings to match against.
    #
    # Examples
    #
    #   list = %w{ foo bar bars }
    #   pattern = 'br'
    #   God.pattern_match(list, pattern)
    #   # => ['bar', 'bars']
    #
    # Returns the Array of matching name Strings.
    def self.pattern_match(pattern, list)
      regex = pattern.chars.join('.*')

      list.grep(Regexp.new(regex)).sort_by(&:size)
    end
  end

  # Runs immediately before the program exits. If $run is true,
  # start god, if $run is false, exit normally.
  #
  # Returns nothing.
  at_exit do
    God.at_exit if $run
  end

end

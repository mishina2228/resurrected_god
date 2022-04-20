# frozen_string_literal: true

module God
  module CLI
    class Run
      def initialize(options)
        @options = options

        dispatch
      end

      def dispatch
        # have at_exit start god
        $run = true

        require 'god/sys_logger' if @options[:syslog]

        # run
        if @options[:daemonize]
          run_daemonized
        else
          run_in_front
        end
      end

      def attach
        process = System::Process.new(@options[:attach])
        Thread.new do
          loop do
            unless process.exists?
              applog(nil, :info, "Going down because attached process #{@options[:attach]} exited")
              exit!
            end
            sleep 5
          end
        end
      end

      def default_run
        # make sure we have STDIN/STDOUT redirected immediately
        setup_logging

        # start attached pid watcher if necessary
        attach if @options[:attach]

        God.port = @options[:port] if @options[:port]

        God::EventHandler.load if @options[:events]

        # set log level, defaults to WARN
        God.log_level = if @options[:log_level]
                          @options[:log_level]
                        else
                          @options[:daemonize] ? :warn : :info
                        end

        if @options[:config]
          abort "File not found: #{@options[:config]}" if !@options[:config].include?('*') && !File.exist?(@options[:config])

          # start the event handler
          God::EventHandler.start if God::EventHandler.loaded?

          load_config @options[:config]
        end
        setup_logging
      end

      def run_in_front
        require 'god'

        default_run
      end

      def run_daemonized
        # trap and ignore SIGHUP
        Signal.trap('HUP') {} # block must be passed
        # trap and log-reopen SIGUSR1
        Signal.trap('USR1') { setup_logging }

        pid = fork do
          require 'god'

          # set pid if requested
          God.pid = @options[:pid] if @options[:pid] # and as daemon

          default_run

          unless God::EventHandler.loaded?
            puts
            puts '***********************************************************************'
            puts '*'
            puts '* Event conditions are not available for your installation of god.'
            puts '* You may still use and write custom conditions using the poll system'
            puts '*'
            puts '***********************************************************************'
            puts
          end
        rescue => e
          puts e.message
          puts e.backtrace.join("\n")
          abort 'There was a fatal system error while starting god (see above)'
        end

        File.write(@options[:pid], pid) if @options[:pid]

        ::Process.detach pid

        exit
      end

      def setup_logging
        log_file = God.log_file
        log_file = File.expand_path(@options[:log]) if @options[:log]
        log_file = '/dev/null' if !log_file && @options[:daemonize]
        return unless log_file

        puts "Sending output to log file: #{log_file}" unless @options[:daemonize]

        # reset file descriptors
        $stdin.reopen '/dev/null'
        $stdout.reopen(log_file, 'a')
        $stderr.reopen $stdout
        $stdout.sync = true
      end

      def load_config(config)
        files = File.directory?(config) ? Dir['**/*.god'] : Dir[config]
        abort 'No files could be found' if files.empty?
        files.each do |god_file|
          abort "File '#{god_file}' could not be loaded" unless load_god_file(god_file)
        end
      end

      def load_god_file(god_file)
        applog(nil, :info, "Loading #{god_file}")
        load File.expand_path(god_file)
        true
      rescue Exception => e
        raise if e.instance_of?(SystemExit)

        puts "There was an error in #{god_file}"
        puts "\t#{e.message}"
        puts "\t#{e.backtrace.join("\n\t")}"
        false
      end
    end
  end
end

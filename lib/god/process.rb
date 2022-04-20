# frozen_string_literal: true

module God
  class Process
    WRITES_PID = [:start, :restart].freeze

    attr_accessor :name, :uid, :gid, :log, :log_cmd, :err_log, :err_log_cmd,
                  :start, :stop, :restart, :unix_socket, :chroot, :env, :dir,
                  :stop_timeout, :stop_signal, :umask

    def initialize
      self.log = '/dev/null'

      @pid_file = nil
      @tracking_pid = true
      @user_log = false
      @pid = nil
      @unix_socket = nil
      @log_cmd = nil
      @stop_timeout = God::STOP_TIMEOUT_DEFAULT
      @stop_signal = God::STOP_SIGNAL_DEFAULT
    end

    def alive?
      if pid
        System::Process.new(pid).exists?
      else
        false
      end
    end

    def file_writable?(file)
      pid = fork do
        begin
          if uid
            user_method = uid.is_a?(Integer) ? :getpwuid : :getpwnam
            uid_num = Etc.send(user_method, uid).uid
            gid_num = Etc.send(user_method, uid).gid
          end
          if gid
            group_method = gid.is_a?(Integer) ? :getgrgid : :getgrnam
            gid_num = Etc.send(group_method, gid).gid
          end

          ::Dir.chroot(chroot) if chroot
          ::Process.groups = [gid_num] if gid_num
          ::Process.initgroups(uid, gid_num) if uid && gid_num
          ::Process::Sys.setgid(gid_num) if gid_num
          ::Process::Sys.setuid(uid_num) if uid
        rescue ArgumentError, Errno::EPERM, Errno::ENOENT
          exit(1)
        end

        File.writable?(file_in_chroot(file)) ? exit!(0) : exit!(1)
      end

      _wpid, status = ::Process.waitpid2(pid)
      status.exitstatus == 0
    end

    def valid?
      # determine if we're tracking pid or not
      pid_file

      valid = true

      # a start command must be specified
      if start.nil?
        valid = false
        applog(self, :error, 'No start command was specified')
      end

      # uid must exist if specified
      if uid
        begin
          Etc.getpwnam(uid)
        rescue ArgumentError
          valid = false
          applog(self, :error, "UID for '#{uid}' does not exist")
        end
      end

      # gid must exist if specified
      if gid
        begin
          Etc.getgrnam(gid)
        rescue ArgumentError
          valid = false
          applog(self, :error, "GID for '#{gid}' does not exist")
        end
      end

      # dir must exist and be a directory if specified
      if dir
        if !File.exist?(dir)
          valid = false
          applog(self, :error, "Specified directory '#{dir}' does not exist")
        elsif !File.directory?(dir)
          valid = false
          applog(self, :error, "Specified directory '#{dir}' is not a directory")
        end
      end

      # pid dir must exist if specified
      if !@tracking_pid && !File.exist?(File.dirname(pid_file))
        valid = false
        applog(self, :error, "PID file directory '#{File.dirname(pid_file)}' does not exist")
      end

      # pid dir must be writable if specified
      if !@tracking_pid && File.exist?(File.dirname(pid_file)) && !file_writable?(File.dirname(pid_file))
        valid = false
        applog(self, :error, "PID file directory '#{File.dirname(pid_file)}' is not writable by #{uid || Etc.getlogin}")
      end

      # log dir must exist
      unless File.exist?(File.dirname(log))
        valid = false
        applog(self, :error, "Log directory '#{File.dirname(log)}' does not exist")
      end

      # log file or dir must be writable
      if File.exist?(log)
        unless file_writable?(log)
          valid = false
          applog(self, :error, "Log file '#{log}' exists but is not writable by #{uid || Etc.getlogin}")
        end
      else
        unless file_writable?(File.dirname(log))
          valid = false
          applog(self, :error, "Log directory '#{File.dirname(log)}' is not writable by #{uid || Etc.getlogin}")
        end
      end

      # chroot directory must exist and have /dev/null in it
      if chroot
        unless File.directory?(chroot)
          valid = false
          applog(self, :error, "CHROOT directory '#{chroot}' does not exist")
        end

        unless File.exist?(File.join(chroot, '/dev/null'))
          valid = false
          applog(self, :error, "CHROOT directory '#{chroot}' does not contain '/dev/null'")
        end
      end

      valid
    end

    # DON'T USE THIS INTERNALLY. Use the instance variable. -- Kev
    # No really, trust me. Use the instance variable.
    def pid_file=(value)
      # if value is nil, do the right thing
      @tracking_pid = if value
                        false
                      else
                        true
                      end

      @pid_file = value
    end

    def pid_file
      @pid_file ||= default_pid_file
    end

    # Fetch the PID from pid_file. If the pid_file does not
    # exist, then use the PID from the last time it was read.
    # If it has never been read, then return nil.
    #
    # Returns Integer(pid) or nil
    def pid
      contents = File.read(pid_file).strip rescue ''
      real_pid = /^\d+$/.match?(contents) ? contents.to_i : nil

      if real_pid
        @pid = real_pid
        real_pid
      else
        @pid
      end
    end

    # Send the given signal to this process.
    #
    # Returns nothing
    def signal(sig)
      sig = sig.to_i if sig.to_i != 0
      applog(self, :info, "#{name} sending signal '#{sig}' to pid #{pid}")
      ::Process.kill(sig, pid) rescue nil
    end

    def start!
      call_action(:start)
    end

    def stop!
      call_action(:stop)
    end

    def restart!
      call_action(:restart)
    end

    def default_pid_file
      File.join(God.pid_file_directory, "#{name}.pid")
    end

    def call_action(action)
      command = send(action)

      if action == :stop && command.nil?
        pid = self.pid
        command = lambda do
          applog(self, :info, "#{name} stop: default lambda killer")

          ::Process.kill(@stop_signal, pid) rescue nil
          applog(self, :info, "#{name} sent SIG#{@stop_signal}")

          # Poll to see if it's dead
          pid_not_found = false
          @stop_timeout.times do
            if pid
              begin
                ::Process.kill(0, pid)
              rescue Errno::ESRCH
                # It died. Good.
                applog(self, :info, "#{name} process stopped")
                return
              end
            else
              applog(self, :warn, "#{name} pid not found in #{pid_file}") unless pid_not_found
              pid_not_found = true
            end

            sleep 1
          end

          ::Process.kill('KILL', pid) rescue nil
          applog(self, :warn, "#{name} still alive after #{@stop_timeout}s; sent SIGKILL")
        end
      end

      case command
      when String
        if [:start, :restart].include?(action) && @tracking_pid
          # double fork god-daemonized processes
          # we don't want to wait for them to finish
          r, w = IO.pipe
          begin
            opid = fork do
              $stdout.reopen(w)
              r.close
              pid = self.spawn(command)
              puts pid.to_s # send pid back to forker
              exit!(0)
            end

            ::Process.waitpid(opid, 0)
            w.close
            pid = r.gets.chomp
          ensure
            # make sure the file descriptors get closed no matter what
            r.close rescue nil
            w.close rescue nil
          end
        else
          # single fork self-daemonizing processes
          # we want to wait for them to finish
          pid = self.spawn(command)
          status = ::Process.waitpid2(pid, 0)
          exit_code = status[1] >> 8

          applog(self, :warn, "#{name} #{action} command exited with non-zero code = #{exit_code}") if exit_code != 0

          ensure_stop if action == :stop
        end

        if @tracking_pid || (@pid_file.nil? && WRITES_PID.include?(action))
          File.write(default_pid_file, pid)

          @tracking_pid = true
          @pid_file = default_pid_file
        end
      when Proc
        # lambda command
        command.call
      else
        raise NotImplementedError
      end
    end

    # Fork/exec the given command, returns immediately
    #   +command+ is the String containing the shell command
    #
    # Returns nothing
    def spawn(command)
      fork do
        File.umask umask if umask
        uid_num = Etc.getpwnam(uid).uid if uid
        gid_num = Etc.getgrnam(gid).gid if gid
        gid_num = Etc.getpwnam(uid).gid if gid.nil? && uid

        ::Dir.chroot(chroot) if chroot
        ::Process.setsid
        ::Process.groups = [gid_num] if gid_num
        ::Process.initgroups(uid, gid_num) if uid && gid_num
        ::Process::Sys.setgid(gid_num) if gid_num
        ::Process::Sys.setuid(uid_num) if uid
        self.dir ||= '/'
        Dir.chdir self.dir
        $0 = command
        $stdin.reopen '/dev/null'
        if log_cmd
          $stdout.reopen IO.popen(log_cmd, 'a')
        else
          $stdout.reopen file_in_chroot(log), 'a'
        end
        if err_log_cmd
          $stderr.reopen IO.popen(err_log_cmd, 'a')
        elsif err_log && (log_cmd || err_log != log)
          $stderr.reopen file_in_chroot(err_log), 'a'
        else
          $stderr.reopen $stdout
        end

        # close any other file descriptors
        3.upto(256) { |fd| IO.new(fd).close rescue nil }

        if env.is_a?(Hash)
          env.each do |(key, value)|
            ENV[key] = value.to_s
          end
        end

        exec command unless command.empty?
      end
    end

    # Ensure that a stop command actually stops the process. Force kill
    # if necessary.
    #
    # Returns nothing
    def ensure_stop
      applog(self, :warn, "#{name} ensuring stop...")

      unless pid
        applog(self, :warn, "#{name} stop called but pid is uknown")
        return
      end

      # Poll to see if it's dead
      @stop_timeout.times do
        begin
          ::Process.kill(0, pid)
        rescue Errno::ESRCH
          # It died. Good.
          return
        end

        sleep 1
      end

      # last resort
      ::Process.kill('KILL', pid) rescue nil
      applog(self, :warn, "#{name} still alive after #{@stop_timeout}s; sent SIGKILL")
    end

    private

    def file_in_chroot(file)
      return file unless chroot

      file.gsub(/^#{Regexp.escape(File.expand_path(chroot))}/, '')
    end
  end
end

# frozen_string_literal: true

module God
  class EventHandler
    @@actions = {}
    @@handler = nil
    @@loaded = false

    def self.loaded?
      @@loaded
    end

    def self.event_system
      @@handler::EVENT_SYSTEM
    end

    def self.load
      case RUBY_PLATFORM
      when /darwin/i, /bsd/i
        require 'god/event_handlers/kqueue_handler'
        @@handler = KQueueHandler
      when /linux/i
        require 'god/event_handlers/netlink_handler'
        @@handler = NetlinkHandler
      else
        raise NotImplementedError, 'Platform not supported for EventHandler'
      end
      @@loaded = true
    rescue Exception
      require 'god/event_handlers/dummy_handler'
      @@handler = DummyHandler
      @@loaded = false
    end

    def self.register(pid, event, &block)
      @@actions[pid] ||= {}
      @@actions[pid][event] = block
      @@handler.register_process(pid, @@actions[pid].keys)
    end

    def self.deregister(pid, event)
      return unless watching_pid?(pid)

      running = ::Process.kill(0, pid.to_i) rescue false
      @@actions[pid].delete(event)
      @@handler.register_process(pid, @@actions[pid].keys) if running
      @@actions.delete(pid) if @@actions[pid].empty?
    end

    def self.call(pid, event, extra_data = {})
      @@actions[pid][event].call(extra_data) if watching_pid?(pid) && @@actions[pid][event]
    end

    def self.watching_pid?(pid)
      @@actions[pid]
    end

    def self.start
      @@thread = Thread.new do
        loop do
          @@handler.handle_events
        rescue Exception => e
          message = format("Unhandled exception (%{class}): %{message}\n%{backtrace}",
                           class: e.class, message: e.message, backtrace: e.backtrace.join("\n"))
          applog(nil, :fatal, message)
        end
      end

      # do a real test to make sure events are working properly
      @@loaded = operational?
    end

    def self.stop
      @@thread&.kill
    end

    def self.operational?
      com = [false]

      Thread.new do
        pid = fork do
          loop { sleep(1) }
        end

        register(pid, :proc_exit) do
          com[0] = true
        end

        ::Process.kill('KILL', pid)
        ::Process.waitpid(pid)

        sleep(0.1)

        deregister(pid, :proc_exit) rescue nil
      rescue => e
        puts e.message
        puts e.backtrace.join("\n")
      end.join

      sleep(0.1)

      com.first
    end
  end
end

module God
  class DummyHandler
    EVENT_SYSTEM = 'none'.freeze

    def self.register_process(pid, events)
      raise NotImplementedError
    end

    def self.handle_events
      raise NotImplementedError
    end
  end
end

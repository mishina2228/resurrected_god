# frozen_string_literal: true

module God
  class Trigger
    class << self
      attr_accessor :triggers # {task.name => condition}
    end

    # init
    self.triggers = {}
    @mutex = Mutex.new

    def self.register(condition)
      @mutex.synchronize do
        triggers[condition.watch.name] ||= []
        triggers[condition.watch.name] << condition
      end
    end

    def self.deregister(condition)
      @mutex.synchronize do
        triggers[condition.watch.name].delete(condition)
        triggers.delete(condition.watch.name) if triggers[condition.watch.name].empty?
      end
    end

    def self.broadcast(task, message, payload)
      return unless triggers[task.name]

      @mutex.synchronize do
        triggers[task.name].each do |t|
          t.process(message, payload)
        end
      end
    end

    def self.reset
      triggers.clear
    end
  end
end

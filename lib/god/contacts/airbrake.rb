# frozen_string_literal: true

# Send a notice to Airbrake (http://airbrake.io/).
#
# apikey - The String API key.

CONTACT_DEPS[:airbrake] = ['airbrake']
CONTACT_DEPS[:airbrake].each do |d|
  require d
end

module God
  module Contacts
    class Airbrake < Contact
      class << self
        attr_accessor :apikey
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'apikey' must be specified", self) if apikey.nil?
        valid
      end

      attr_accessor :apikey

      def notify(message, _time, priority, category, host)
        ::Airbrake.configure {} # block must be passed

        message = +"God: #{message} at #{host}"
        message << " | #{[category, priority].join(' ')}" unless category.to_s.empty? || priority.to_s.empty?

        self.info = if ::Airbrake.notify nil, error_message: message, api_key: arg(:apikey)
                      "sent airbrake notification to #{name}"
                    else
                      "failed to send airbrake notification to #{name}"
                    end
      rescue Object => e
        applog(nil, :info, "failed to send airbrake notification: #{e.message}")
        applog(nil, :debug, e.backtrace.join("\n"))
      end
    end
  end
end

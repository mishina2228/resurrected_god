# frozen_string_literal: true

require 'net/http'
require 'net/https'

module God
  module Conditions
    # Condition Symbol :http_response_code
    # Type: Poll
    #
    # Trigger based on the response from an HTTP request.
    #
    # Parameters
    #   Required
    #     +host+ is the hostname to connect [required]
    #     --one of code_is or code_is_not--
    #     +code_is+ trigger if the response code IS one of these
    #               e.g. 500 or '500' or [404, 500] or %w{404 500}
    #     +code_is_not+ trigger if the response code IS NOT one of these
    #                   e.g. 200 or '200' or [200, 302] or %w{200 302}
    #  Optional
    #     +port+ is the port to connect (default 80)
    #     +path+ is the path to connect (default '/')
    #     +headers+ is the hash of HTTP headers to send (default none)
    #     +times+ is the number of times after which to trigger (default 1)
    #             e.g. 3 (times in a row) or [3, 5] (three out of fives times)
    #     +timeout+ is the time to wait for a connection (default 60.seconds)
    #     +ssl+ should the connection use ssl (default false)
    #
    # Examples
    #
    # Trigger if the response code from www.example.com/foo/bar
    # is not a 200 (or if the connection is refused or times out:
    #
    #   on.condition(:http_response_code) do |c|
    #     c.host = 'www.example.com'
    #     c.path = '/foo/bar'
    #     c.code_is_not = 200
    #   end
    #
    # Trigger if the response code is a 404 or a 500 (will not
    # be triggered by a connection refusal or timeout):
    #
    #   on.condition(:http_response_code) do |c|
    #     c.host = 'www.example.com'
    #     c.path = '/foo/bar'
    #     c.code_is = [404, 500]
    #   end
    #
    # Trigger if the response code is not a 200 five times in a row:
    #
    #   on.condition(:http_response_code) do |c|
    #     c.host = 'www.example.com'
    #     c.path = '/foo/bar'
    #     c.code_is_not = 200
    #     c.times = 5
    #   end
    #
    # Trigger if the response code is not a 200 or does not respond
    # within 10 seconds:
    #
    #   on.condition(:http_response_code) do |c|
    #     c.host = 'www.example.com'
    #     c.path = '/foo/bar'
    #     c.code_is_not = 200
    #     c.timeout = 10
    #   end
    class HttpResponseCode < PollCondition
      attr_accessor :code_is,      # e.g. 500 or '500' or [404, 500] or %w{404 500}
                    :code_is_not,  # e.g. 200 or '200' or [200, 302] or %w{200 302}
                    :times,        # e.g. 3 or [3, 5]
                    :host,         # e.g. www.example.com
                    :port,         # e.g. 8080
                    :ssl,          # e.g. true or false
                    :ca_file,      # e.g /path/to/pem_file for ssl verification (checkout http://curl.haxx.se/ca/cacert.pem)
                    :timeout,      # e.g. 60.seconds
                    :path,         # e.g. '/'
                    :headers       # e.g. {'Host' => 'myvirtual.mydomain.com'}

      def initialize
        super
        self.port = 80
        self.path = '/'
        self.headers = {}
        self.times = [1, 1]
        self.timeout = 60.seconds
        self.ssl = false
        self.ca_file = nil
      end

      def prepare
        self.code_is = Array(code_is).map(&:to_i) if code_is
        self.code_is_not = Array(code_is_not).map(&:to_i) if code_is_not

        self.times = [times, times] if times.is_a?(Integer)

        @timeline = Timeline.new(times[1])
        @history = Timeline.new(times[1])
      end

      def reset
        @timeline.clear
        @history.clear
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'host' must be specified", self) if host.nil?
        valid &= complain("One (and only one) of attributes 'code_is' and 'code_is_not' must be specified", self) if
          (code_is.nil? && code_is_not.nil?) || (code_is && code_is_not)
        valid
      end

      def test
        response = nil

        connection = Net::HTTP.new(host, port)
        connection.use_ssl = port == 443 ? true : ssl
        connection.verify_mode = OpenSSL::SSL::VERIFY_NONE if connection.use_ssl?

        if connection.use_ssl? && ca_file
          File.read(ca_file) # it may raise EOFError
          connection.ca_file = ca_file
          connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        connection.start do |http|
          http.read_timeout = timeout
          response = http.get(path, headers)
        end

        actual_response_code = response.code.to_i
        if code_is&.include?(actual_response_code)
          pass(actual_response_code)
        elsif code_is_not && !code_is_not.include?(actual_response_code)
          pass(actual_response_code)
        else
          fail(actual_response_code)
        end
      rescue Errno::ECONNREFUSED
        code_is ? fail('Refused') : pass('Refused')
      rescue Errno::ECONNRESET
        code_is ? fail('Reset') : pass('Reset')
      rescue EOFError
        code_is ? fail('EOF') : pass('EOF')
      rescue Timeout::Error
        code_is ? fail('Timeout') : pass('Timeout')
      rescue Errno::ETIMEDOUT
        code_is ? fail('Timedout') : pass('Timedout')
      rescue Exception => e
        code_is ? fail(e.class.name) : pass(e.class.name)
      end

      private

      def pass(code)
        @timeline << true
        if @timeline.count { |x| x } >= times.first
          self.info = "http response abnormal #{history(code, true)}"
          true
        else
          self.info = "http response nominal #{history(code, true)}"
          false
        end
      end

      def fail(code)
        @timeline << false
        self.info = "http response nominal #{history(code, false)}"
        false
      end

      def history(code, passed)
        entry = code.to_s.dup
        entry = "*#{entry}" if passed
        @history << entry
        "[#{@history.join(', ')}]"
      end
    end
  end
end

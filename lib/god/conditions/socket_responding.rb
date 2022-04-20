# frozen_string_literal: true

require 'socket'
include Socket::Constants

module God
  module Conditions
    # Condition Symbol :socket_running
    # Type: Poll
    #
    # Trigger when a TCP or UNIX socket is running or not
    #
    # Parameters
    # Required
    #   +family+ is the family of socket: either 'tcp' or 'unix'
    #   --one of port or path--
    #   +port+ is the port (required if +family+ is 'tcp')
    #   +path+ is the path (required if +family+ is 'unix')
    #
    # Optional
    #   +responding+ is the boolean specifying whether you want to trigger if the socket is responding (true)
    #                or if it is not responding (false) (default false)
    #
    # Examples
    #
    # Trigger if the TCP socket on port 80 is not responding or the connection is refused
    #
    # on.condition(:socket_responding) do |c|
    #   c.family = 'tcp'
    #   c.port = '80'
    # end
    #
    # Trigger if the socket is not responding or the connection is refused (use alternate compact +socket+ interface)
    #
    # on.condition(:socket_responding) do |c|
    #   c.socket = 'tcp:80'
    # end
    #
    # Trigger if the socket is responding
    #
    # on.condition(:socket_responding) do |c|
    #   c.socket = 'tcp:80'
    #   c.responding = true
    # end
    #
    # Trigger if the socket is not responding or the connection is refused 5 times in a row
    #
    # on.condition(:socket_responding) do |c|
    #   c.socket = 'tcp:80'
    #   c.times = 5
    # end
    #
    # Trigger if the Unix socket on path '/tmp/sock' is not responding or non-existent
    #
    # on.condition(:socket_responding) do |c|
    #   c.family = 'unix'
    #   c.path = '/tmp/sock'
    # end
    #
    class SocketResponding < PollCondition
      attr_accessor :family, :addr, :port, :path, :times, :responding

      def initialize
        super
        # default to tcp on the localhost
        self.family = 'tcp'
        self.addr = '127.0.0.1'
        # Set these to nil/0 values
        self.port = 0
        self.path = nil
        self.responding = false

        self.times = [1, 1]
      end

      def prepare
        self.times = [times, times] if times.is_a?(Integer)

        @timeline = Timeline.new(times[1])
        @history = Timeline.new(times[1])
      end

      def reset
        @timeline.clear
        @history.clear
      end

      def socket=(socket)
        components = socket.split(':')
        if components.size == 3
          @family, @addr, @port = components
          @port = @port.to_i
        elsif /^tcp$/.match?(components[0])
          @family = components[0]
          @port = components[1].to_i
        elsif /^unix$/.match?(components[0])
          @family = components[0]
          @path = components[1]
        end
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'port' must be specified for tcp sockets", self) if family == 'tcp' && @port == 0
        valid &= complain("Attribute 'path' must be specified for unix sockets", self) if family == 'unix' && path.nil?
        valid = false unless %w[tcp unix].member?(family)
        valid
      end

      def test
        self.info = []
        case family
        when 'tcp'
          begin
            s = TCPSocket.new(addr, port)
          rescue SystemCallError
          end
          status = responding != s.nil?
        when 'unix'
          begin
            s = UNIXSocket.new(path)
          rescue SystemCallError
          end
          status = responding != s.nil?
        else
          status = false
        end
        @timeline.push(status)
        history = @timeline.map { |t| t ? '*' : '' }.join(',')
        if @timeline.count { |x| x } >= times.first
          self.info = "socket out of bounds [#{history}]"
          true
        else
          false
        end
      end
    end
  end
end

# frozen_string_literal: true

module God
  module System
    class PortablePoller
      def initialize(pid)
        @pid = pid
      end

      # Memory usage in kilobytes (resident set size)
      def memory
        ps_int('rss')
      end

      # Percentage memory usage
      def percent_memory
        ps_float('%mem')
      end

      # Percentage CPU usage
      def percent_cpu
        ps_float('%cpu')
      end

      private

      def ps_int(keyword)
        `ps -o #{keyword}= -p #{@pid}`.to_i
      end

      def ps_float(keyword)
        `ps -o #{keyword}= -p #{@pid}`.to_f
      end
    end
  end
end

module Flagstack
  class Telemetry
    class MetricStorage
      def initialize
        @mutex = Mutex.new
        @storage = Hash.new(0)
      end

      def increment(metric)
        @mutex.synchronize do
          @storage[metric] += 1
        end
      end

      def drain
        @mutex.synchronize do
          metrics = @storage.dup
          @storage.clear
          metrics.freeze
        end
      end

      def empty?
        @mutex.synchronize { @storage.empty? }
      end

      def size
        @mutex.synchronize { @storage.size }
      end
    end
  end
end

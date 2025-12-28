module Flagstack
  class Telemetry
    class Metric
      attr_reader :key, :time, :result

      def initialize(key, result, time = Time.now)
        @key = key.to_s
        @result = !!result
        @time = time.to_i / 60 * 60 # Round to minute
      end

      def as_json
        {
          "key" => key,
          "time" => time,
          "result" => result
        }
      end

      def eql?(other)
        self.class.eql?(other.class) &&
          @key == other.key &&
          @time == other.time &&
          @result == other.result
      end
      alias :== :eql?

      def hash
        [self.class, @key, @time, @result].hash
      end
    end
  end
end

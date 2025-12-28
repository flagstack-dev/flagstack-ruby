require "zlib"
require "json"
require "securerandom"

module Flagstack
  class Telemetry
    class Submitter
      MAX_RETRIES = 3

      def initialize(client, config)
        @client = client
        @config = config
        @request_id = SecureRandom.uuid
      end

      def call(metrics)
        return if metrics.empty?

        body = build_body(metrics)
        compressed = gzip(body)

        response = submit_with_retry(compressed)
        handle_response(response) if response
      rescue => e
        @config.log("Telemetry submission failed: #{e.message}", level: :error)
      end

      private

      def build_body(metrics)
        {
          request_id: @request_id,
          metrics: metrics.map do |metric, count|
            metric.as_json.merge("value" => count)
          end
        }.to_json
      end

      def gzip(body)
        io = StringIO.new
        io.set_encoding("BINARY")
        gz = Zlib::GzipWriter.new(io)
        gz.write(body)
        gz.close
        io.string
      end

      def submit_with_retry(body)
        retries = 0
        begin
          @client.post_telemetry(body)
        rescue => e
          retries += 1
          if retries < MAX_RETRIES
            sleep(backoff_delay(retries))
            retry
          end
          raise
        end
      end

      def backoff_delay(attempt)
        # Exponential backoff: 1s, 2s, 4s
        (2 ** (attempt - 1)) + rand(0.0..0.5)
      end

      def handle_response(response)
        return unless response

        # Server can control telemetry via headers
        if (interval = response["Telemetry-Interval"])
          @config.telemetry_interval = interval.to_i
          @config.log("Telemetry interval updated to #{interval}s", level: :debug)
        end

        if response["Telemetry-Shutdown"] == "true"
          @config.telemetry_enabled = false
          @config.log("Telemetry shutdown requested by server", level: :info)
        end
      end
    end
  end
end

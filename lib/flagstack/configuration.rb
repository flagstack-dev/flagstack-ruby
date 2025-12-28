require "logger"

module Flagstack
  class Configuration
    # Authentication
    attr_accessor :token

    # Server
    attr_accessor :url

    # HTTP settings
    attr_accessor :read_timeout, :open_timeout, :write_timeout

    # Sync settings
    attr_accessor :sync_interval, :sync_method

    # Local adapter for fallback/caching
    attr_accessor :local_adapter

    # Telemetry settings
    attr_accessor :telemetry_enabled, :telemetry_interval

    # Logging
    attr_accessor :logger, :debug_output

    # Instrumentation (for monitoring systems)
    attr_accessor :instrumenter

    def initialize(options = {})
      setup_auth(options)
      setup_http(options)
      setup_sync(options)
      setup_telemetry(options)
      setup_logging(options)
      setup_instrumentation(options)
    end

    def validate!
      raise ConfigurationError, "Token is required. Set FLAGSTACK_TOKEN or pass token option." if token.nil? || token.empty?
    end

    def log(message, level: :debug)
      logger&.send(level, "[Flagstack] #{message}")
    end

    def instrument(name, payload = {}, &block)
      if instrumenter
        instrumenter.instrument("flagstack.#{name}", payload, &block)
      elsif block
        yield payload
      end
    end

    def environment_from_token
      return :unknown unless token

      prefix = token.split("_")[1]
      case prefix
      when "live" then :production
      when "test" then :staging
      when "dev" then :development
      when "personal" then :personal
      else :unknown
      end
    end

    private

    def setup_auth(options)
      @token = options.fetch(:token) { ENV["FLAGSTACK_TOKEN"] }
      @url = options.fetch(:url) { ENV.fetch("FLAGSTACK_URL", "https://flagstack.io") }
    end

    def setup_http(options)
      @read_timeout = options.fetch(:read_timeout, 5)
      @open_timeout = options.fetch(:open_timeout, 2)
      @write_timeout = options.fetch(:write_timeout, 5)
    end

    def setup_sync(options)
      interval = options.fetch(:sync_interval) { ENV.fetch("FLAGSTACK_SYNC_INTERVAL", 30).to_i }
      @sync_interval = [interval, 10].max  # Minimum 10 seconds

      @sync_method = options.fetch(:sync_method, :poll)
      @local_adapter = options[:local_adapter]
    end

    def setup_telemetry(options)
      @telemetry_enabled = options.fetch(:telemetry_enabled) {
        ENV.fetch("FLAGSTACK_TELEMETRY_ENABLED", "true") == "true"
      }
      @telemetry_interval = options.fetch(:telemetry_interval) {
        ENV.fetch("FLAGSTACK_TELEMETRY_INTERVAL", 60).to_i
      }
    end

    def setup_logging(options)
      @debug_output = options[:debug_output]
      @logger = options.fetch(:logger) do
        if defined?(Rails) && Rails.respond_to?(:logger)
          Rails.logger
        else
          Logger.new($stdout, level: Logger::INFO)
        end
      end
    end

    def setup_instrumentation(options)
      @instrumenter = options[:instrumenter]
    end
  end
end

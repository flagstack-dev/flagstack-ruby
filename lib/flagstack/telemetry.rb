module Flagstack
  class Telemetry
    attr_reader :storage

    def initialize(client, config)
      @client = client
      @config = config
      @storage = MetricStorage.new
      @pid = Process.pid
      @started = false
      @mutex = Mutex.new
    end

    def start
      @mutex.synchronize do
        return if @started
        start_timer
        @started = true
        @config.log("Telemetry started (interval: #{@config.telemetry_interval}s)", level: :info)
      end
    end

    def stop
      @mutex.synchronize do
        return unless @started
        @timer_thread&.kill
        @timer_thread = nil
        flush
        @started = false
        @config.log("Telemetry stopped", level: :info)
      end
    end

    def record(feature_key, result)
      return unless @config.telemetry_enabled

      # Fork detection - restart if PID changed
      check_fork

      metric = Metric.new(feature_key, result)
      @storage.increment(metric)
    end

    def flush
      return if @storage.empty?

      metrics = @storage.drain
      submitter = Submitter.new(@client, @config)

      # Submit in background thread to not block
      Thread.new { submitter.call(metrics) }
    end

    def running?
      @started
    end

    private

    def start_timer
      @timer_thread = Thread.new do
        loop do
          sleep(@config.telemetry_interval)
          flush if @started
        end
      end
      @timer_thread.abort_on_exception = false
    end

    def check_fork
      return if @pid == Process.pid

      @mutex.synchronize do
        return if @pid == Process.pid

        @config.log("Fork detected, restarting telemetry", level: :info)

        # Drain any pending metrics before fork reset
        # Note: We can't submit in parent process after fork, so we lose these
        # metrics. This is a known limitation of forking servers.
        # The metrics collected in the child process will be submitted normally.
        unless @storage.empty?
          @config.log("Discarding #{@storage.size} metrics from parent process after fork", level: :debug)
        end

        @pid = Process.pid
        @storage = MetricStorage.new
        @timer_thread&.kill
        @timer_thread = nil
        start_timer if @started
      end
    end
  end
end

# Load nested classes after the Telemetry class is defined
require "flagstack/telemetry/metric"
require "flagstack/telemetry/metric_storage"
require "flagstack/telemetry/submitter"

module Flagstack
  class Poller
    def initialize(synchronizer, config)
      @synchronizer = synchronizer
      @config = config
      @running = false
      @thread = nil
      @pid = Process.pid
    end

    def start
      return if @running

      @running = true
      @thread = Thread.new { run }
      @thread.abort_on_exception = false
    end

    def stop
      @running = false
      @thread&.wakeup rescue nil
      @thread&.join(2)
      @thread = nil
    end

    def running?
      @running && @thread&.alive?
    end

    private

    def run
      while @running
        # Check for fork (important for Puma, Unicorn, etc.)
        if forked?
          reset_after_fork
          next
        end

        sleep_with_jitter

        begin
          @synchronizer.sync
        rescue => e
          @config.log("Poll sync failed: #{e.message}", level: :error)
        end
      end
    end

    def sleep_with_jitter
      # Add 10% jitter to prevent thundering herd
      jitter = @config.sync_interval * 0.1 * rand
      sleep(@config.sync_interval + jitter)
    end

    def forked?
      Process.pid != @pid
    end

    def reset_after_fork
      @config.log("Fork detected, resetting poller", level: :debug)
      @pid = Process.pid
      @running = false
    end
  end
end

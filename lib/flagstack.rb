require "flagstack/version"
require "flagstack/configuration"
require "flagstack/client"
require "flagstack/synchronizer"
require "flagstack/poller"
require "flagstack/telemetry"

module Flagstack
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end

  class << self
    attr_reader :configuration

    # Create a new Flagstack-backed Flipper instance
    #
    #   flipper = Flagstack.new(token: "fs_live_xxx")
    #   flipper.enabled?(:feature)
    #   flipper.enabled?(:feature, user)
    #
    def new(options = {})
      config = Configuration.new(options)
      yield config if block_given?
      config.validate!

      Instance.new(config).flipper
    end

    # Configure the default Flagstack instance
    # Returns a Flipper instance that reads from local adapter synced with Flagstack
    #
    #   Flagstack.configure do |config|
    #     config.token = ENV["FLAGSTACK_TOKEN"]
    #   end
    #
    #   # Now use Flipper as normal
    #   Flipper.enabled?(:feature)
    #
    def configure(options = {})
      @configuration = Configuration.new(options)
      yield @configuration if block_given?
      @configuration.validate!

      @instance = Instance.new(@configuration)

      # Set as default Flipper instance so Flipper.enabled? uses our adapter
      Flipper.configure do |config|
        config.default { @instance.flipper }
      end

      # Initial sync
      @instance.sync

      # Start background polling
      @instance.start_poller if @configuration.sync_method == :poll

      # Start telemetry
      @instance.start_telemetry

      @instance.flipper
    end

    # Get the Flipper instance
    def flipper
      @instance&.flipper
    end

    # Force sync from Flagstack to local adapter
    def sync
      @instance&.sync
    end

    # Reset everything (useful for testing)
    def reset!
      @instance&.stop_poller
      @instance&.stop_telemetry
      @instance = nil
      @configuration = nil
    end

    # Shutdown telemetry and polling gracefully
    def shutdown
      @instance&.stop_telemetry
      @instance&.stop_poller
    end

    # Check connectivity to Flagstack server
    # Returns { ok: boolean, message: string }
    def health_check
      @instance&.client&.health_check || { ok: false, message: "Not configured" }
    end

    # ==========================================================================
    # Flipper-compatible API
    # These methods provide a clean abstraction that can be backed by Flipper
    # today, but replaced with a custom backend in the future.
    # ==========================================================================

    # Check if a feature is enabled
    #
    #   Flagstack.enabled?(:new_feature)
    #   Flagstack.enabled?(:new_feature, current_user)
    #
    def enabled?(feature, actor = nil)
      return false unless @instance&.flipper

      if actor
        @instance.flipper.enabled?(feature, actor)
      else
        @instance.flipper.enabled?(feature)
      end
    end

    # Check if a feature is disabled
    #
    #   Flagstack.disabled?(:new_feature)
    #   Flagstack.disabled?(:new_feature, current_user)
    #
    def disabled?(feature, actor = nil)
      !enabled?(feature, actor)
    end

    # Enable a feature globally
    #
    #   Flagstack.enable(:new_feature)
    #
    def enable(feature)
      @instance&.flipper&.[](feature)&.enable
    end

    # Disable a feature globally
    #
    #   Flagstack.disable(:new_feature)
    #
    def disable(feature)
      @instance&.flipper&.[](feature)&.disable
    end

    # Enable a feature for a specific actor
    #
    #   Flagstack.enable_actor(:new_feature, current_user)
    #
    def enable_actor(feature, actor)
      @instance&.flipper&.[](feature)&.enable_actor(actor)
    end

    # Disable a feature for a specific actor
    #
    #   Flagstack.disable_actor(:new_feature, current_user)
    #
    def disable_actor(feature, actor)
      @instance&.flipper&.[](feature)&.disable_actor(actor)
    end

    # Enable a feature for a group
    #
    #   Flagstack.enable_group(:new_feature, :admins)
    #
    def enable_group(feature, group)
      @instance&.flipper&.[](feature)&.enable_group(group)
    end

    # Disable a feature for a group
    #
    #   Flagstack.disable_group(:new_feature, :admins)
    #
    def disable_group(feature, group)
      @instance&.flipper&.[](feature)&.disable_group(group)
    end

    # Enable a feature for a percentage of actors
    #
    #   Flagstack.enable_percentage_of_actors(:new_feature, 25)
    #
    def enable_percentage_of_actors(feature, percentage)
      @instance&.flipper&.[](feature)&.enable_percentage_of_actors(percentage)
    end

    # Disable percentage of actors gate
    #
    #   Flagstack.disable_percentage_of_actors(:new_feature)
    #
    def disable_percentage_of_actors(feature)
      @instance&.flipper&.[](feature)&.disable_percentage_of_actors
    end

    # Enable a feature for a percentage of time
    #
    #   Flagstack.enable_percentage_of_time(:new_feature, 50)
    #
    def enable_percentage_of_time(feature, percentage)
      @instance&.flipper&.[](feature)&.enable_percentage_of_time(percentage)
    end

    # Disable percentage of time gate
    #
    #   Flagstack.disable_percentage_of_time(:new_feature)
    #
    def disable_percentage_of_time(feature)
      @instance&.flipper&.[](feature)&.disable_percentage_of_time
    end

    # Access a feature by name (returns a Feature object)
    #
    #   Flagstack[:new_feature].enabled?
    #   Flagstack[:new_feature].enable
    #
    def [](feature)
      @instance&.flipper&.[](feature)
    end

    # List all features
    #
    #   Flagstack.features
    #
    def features
      @instance&.flipper&.features || []
    end

    # Register a group for use with enable_group
    #
    #   Flagstack.register(:admins) { |actor| actor.admin? }
    #
    def register(group, &block)
      Flipper.register(group, &block)
    end

    # Auto-configure when FLAGSTACK_TOKEN is present
    def set_default
      return unless ENV["FLAGSTACK_TOKEN"]
      return if @configuration # Already configured

      configure
    rescue => e
      # Don't fail app boot if Flagstack is misconfigured
      warn "[Flagstack] Auto-configuration failed: #{e.message}"
    end
  end

  # Instance holds the configured state for a Flagstack setup
  class Instance
    attr_reader :configuration, :client, :local_adapter, :flipper, :telemetry

    def initialize(configuration)
      @configuration = configuration
      @client = Client.new(configuration)
      @local_adapter = configuration.local_adapter || default_adapter
      @flipper = Flipper.new(@local_adapter, instrumenter: TelemetryInstrumenter.new(self))
      @synchronizer = Synchronizer.new(
        client: @client,
        flipper: @flipper,
        config: @configuration
      )
      @poller = nil
      @telemetry = Telemetry.new(@client, @configuration)
    end

    def sync
      @synchronizer.sync
    end

    def start_poller
      return if @poller&.running?

      @poller = Poller.new(@synchronizer, @configuration)
      @poller.start
      @configuration.log("Started background poller (interval: #{@configuration.sync_interval}s)", level: :info)
    end

    def stop_poller
      @poller&.stop
      @poller = nil
    end

    def start_telemetry
      return unless @configuration.telemetry_enabled
      @telemetry.start
    end

    def stop_telemetry
      @telemetry&.stop
    end

    def record_telemetry(feature_key, result)
      @telemetry&.record(feature_key, result)
    end

    private

    def default_adapter
      # Try ActiveRecord first, fall back to Memory
      if defined?(Flipper::Adapters::ActiveRecord)
        begin
          Flipper::Adapters::ActiveRecord.new
        rescue => e
          @configuration.log("Could not create ActiveRecord adapter: #{e.message}, using Memory", level: :warn)
          Flipper::Adapters::Memory.new
        end
      else
        Flipper::Adapters::Memory.new
      end
    end
  end

  # Instrumenter that records telemetry for feature flag checks
  class TelemetryInstrumenter
    def initialize(instance)
      @instance = instance
    end

    def instrument(name, payload = {})
      result = yield payload if block_given?

      # Record telemetry for feature_operation events
      if name == "feature_operation.flipper" && payload[:operation] == :enabled?
        feature_name = payload[:feature_name]
        @instance.record_telemetry(feature_name, payload[:result]) if feature_name
      end

      result
    end
  end
end

# Load Railtie if Rails is present
require "flagstack/railtie" if defined?(Rails::Railtie)

# Auto-configure when token is present (after Rails initializers if in Rails)
unless defined?(Rails::Railtie)
  Flagstack.set_default
end

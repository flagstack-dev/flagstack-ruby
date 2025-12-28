module Flagstack
  # Synchronizes features from Flagstack into the local adapter.
  # This mirrors Flipper Cloud's approach: remote is source of truth,
  # local adapter is kept in sync for fast reads.
  class Synchronizer
    def initialize(client:, flipper:, config:)
      @client = client
      @flipper = flipper
      @config = config
    end

    # Pull features from Flagstack and write them into local adapter
    def sync
      @config.log("Synchronizing features from Flagstack", level: :debug)

      data = @client.sync
      return false unless data && data["features"]

      features = data["features"]
      @config.log("Received #{features.size} features from Flagstack", level: :debug)

      features.each do |feature_data|
        sync_feature(feature_data)
      end

      @config.log("Synchronized #{features.size} features to local adapter", level: :info)
      true
    rescue => e
      @config.log("Sync failed: #{e.message}", level: :error)
      false
    end

    private

    def sync_feature(feature_data)
      key = feature_data["key"]
      gates = feature_data["gates"] || {}
      enabled = feature_data["enabled"]
      feature = @flipper[key]

      # Clear existing gates first (disable everything)
      feature.disable

      # Sync boolean gate from the feature's enabled status
      if enabled == true
        feature.enable
      end
      # If false or nil, feature stays disabled from the disable above

      # Sync actor gates
      (gates["actors"] || []).each do |actor_id|
        actor = Actor.new(actor_id)
        feature.enable_actor(actor)
      end

      # Sync group gates
      (gates["groups"] || []).each do |group_name|
        feature.enable_group(group_name.to_sym)
      end

      # Sync percentage of actors
      if gates["percentage_of_actors"]&.positive?
        feature.enable_percentage_of_actors(gates["percentage_of_actors"])
      end

      # Sync percentage of time
      if gates["percentage_of_time"]&.positive?
        feature.enable_percentage_of_time(gates["percentage_of_time"])
      end
    end
  end

  # Simple actor class for sync operations
  class Actor
    attr_reader :flipper_id

    def initialize(id)
      @flipper_id = id
    end
  end
end

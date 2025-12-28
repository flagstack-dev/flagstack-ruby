require "spec_helper"

RSpec.describe Flagstack do
  let(:sync_response) do
    {
      "features" => [
        {
          "key" => "new_checkout",
          "name" => "New Checkout",
          "description" => "A new checkout flow",
          "enabled" => true,
          "gates" => {}
        },
        {
          "key" => "beta_feature",
          "name" => "Beta Feature",
          "description" => "A beta feature",
          "enabled" => false,
          "gates" => { "actors" => ["User_1", "User_2"] }
        },
        {
          "key" => "percentage_feature",
          "name" => "Percentage Feature",
          "description" => "A percentage-based feature",
          "enabled" => false,
          "gates" => { "percentage_of_actors" => 50 }
        }
      ],
      "environment" => { "name" => "Production", "kind" => "production" },
      "synced_at" => "2024-12-19T00:00:00Z"
    }
  end

  before do
    stub_request(:get, "https://flagstack.io/api/v1/sync")
      .to_return(
        status: 200,
        body: sync_response.to_json,
        headers: { "Content-Type" => "application/json", "ETag" => "abc123" }
      )

    # Stub telemetry endpoint
    stub_request(:post, "https://flagstack.io/api/v1/telemetry")
      .to_return(status: 202, body: "", headers: { "Telemetry-Interval" => "60" })
  end

  describe ".configure" do
    it "raises error without token" do
      expect {
        Flagstack.configure do |config|
          config.token = nil
        end
      }.to raise_error(Flagstack::ConfigurationError)
    end

    it "returns a Flipper instance" do
      flipper = Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end

      expect(flipper).to be_a(Flipper::DSL)
    end

    it "syncs features to local adapter on configure" do
      flipper = Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end

      expect(flipper.features.map(&:key)).to include("new_checkout", "beta_feature")
    end
  end

  describe "Flipper integration" do
    let(:flipper) do
      Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end
    end

    it "returns true for enabled boolean feature" do
      expect(flipper.enabled?(:new_checkout)).to be true
    end

    it "returns false for disabled feature" do
      expect(flipper.enabled?(:beta_feature)).to be false
    end

    it "returns false for unknown feature" do
      expect(flipper.enabled?(:nonexistent)).to be false
    end

    context "with actor" do
      let(:user) { double("User", flipper_id: "User_1") }
      let(:other_user) { double("User", flipper_id: "User_999") }

      it "returns true when actor is in actors list" do
        expect(flipper.enabled?(:beta_feature, user)).to be true
      end

      it "returns false when actor is not in actors list" do
        expect(flipper.enabled?(:beta_feature, other_user)).to be false
      end
    end

    context "with percentage of actors" do
      let(:user) { double("User", flipper_id: "User_123") }

      it "is deterministic for same actor" do
        results = 10.times.map { flipper.enabled?(:percentage_feature, user) }
        expect(results.uniq.size).to eq(1)
      end
    end
  end

  describe ".new" do
    it "creates a Flipper instance without affecting global state" do
      flipper = Flagstack.new(token: "fs_live_test")
      expect(flipper).to be_a(Flipper::DSL)
      expect(Flagstack.configuration).to be_nil
    end
  end

  describe ".flipper" do
    it "returns nil before configure" do
      expect(Flagstack.flipper).to be_nil
    end

    it "returns the Flipper instance after configure" do
      Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end

      expect(Flagstack.flipper).to be_a(Flipper::DSL)
    end
  end

  describe ".sync" do
    it "syncs features from Flagstack to local adapter" do
      flipper = Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end

      # Modify the stub to return different data
      stub_request(:get, "https://flagstack.io/api/v1/sync")
        .to_return(
          status: 200,
          body: {
            "features" => [
              { "key" => "new_feature", "enabled" => true, "gates" => {} }
            ]
          }.to_json,
          headers: { "ETag" => "new123" }
        )

      Flagstack.sync

      expect(flipper.enabled?(:new_feature)).to be true
    end
  end

  describe "local features" do
    it "preserves local features not in Flagstack" do
      flipper = Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end

      # Add a local-only feature
      flipper.enable(:local_only_feature)

      expect(flipper.enabled?(:local_only_feature)).to be true
      expect(flipper.enabled?(:new_checkout)).to be true  # Flagstack feature still works
    end
  end

  # ==========================================================================
  # Flagstack API (Flipper-compatible methods)
  # ==========================================================================

  describe "Flagstack API" do
    before do
      Flagstack.configure do |config|
        config.token = "fs_live_test"
        config.sync_method = :manual
      end
    end

    describe ".enabled?" do
      it "returns true for enabled feature" do
        expect(Flagstack.enabled?(:new_checkout)).to be true
      end

      it "returns false for disabled feature" do
        expect(Flagstack.enabled?(:beta_feature)).to be false
      end

      it "returns false for unknown feature" do
        expect(Flagstack.enabled?(:nonexistent)).to be false
      end

      context "with actor" do
        let(:user) { double("User", flipper_id: "User_1") }
        let(:other_user) { double("User", flipper_id: "User_999") }

        it "returns true when actor is enabled" do
          expect(Flagstack.enabled?(:beta_feature, user)).to be true
        end

        it "returns false when actor is not enabled" do
          expect(Flagstack.enabled?(:beta_feature, other_user)).to be false
        end
      end

      it "returns false when not configured" do
        Flagstack.reset!
        expect(Flagstack.enabled?(:new_checkout)).to be false
      end
    end

    describe ".disabled?" do
      it "returns false for enabled feature" do
        expect(Flagstack.disabled?(:new_checkout)).to be false
      end

      it "returns true for disabled feature" do
        expect(Flagstack.disabled?(:beta_feature)).to be true
      end
    end

    describe ".enable and .disable" do
      it "enables a feature" do
        Flagstack.enable(:my_feature)
        expect(Flagstack.enabled?(:my_feature)).to be true
      end

      it "disables a feature" do
        Flagstack.enable(:my_feature)
        Flagstack.disable(:my_feature)
        expect(Flagstack.enabled?(:my_feature)).to be false
      end
    end

    describe ".enable_actor and .disable_actor" do
      let(:user) { double("User", flipper_id: "User_42") }

      it "enables for a specific actor" do
        Flagstack.enable_actor(:actor_feature, user)
        expect(Flagstack.enabled?(:actor_feature, user)).to be true
      end

      it "disables for a specific actor" do
        Flagstack.enable_actor(:actor_feature, user)
        Flagstack.disable_actor(:actor_feature, user)
        expect(Flagstack.enabled?(:actor_feature, user)).to be false
      end
    end

    describe ".enable_group and .disable_group" do
      let(:admin) { double("User", flipper_id: "User_admin", admin?: true) }
      let(:regular) { double("User", flipper_id: "User_regular", admin?: false) }

      before do
        # Only register if not already registered
        unless Flipper.groups.map(&:name).include?(:admins)
          Flagstack.register(:admins) { |actor| actor.respond_to?(:admin?) && actor.admin? }
        end
      end

      it "enables for a group" do
        Flagstack.enable_group(:admin_feature, :admins)
        expect(Flagstack.enabled?(:admin_feature, admin)).to be true
        expect(Flagstack.enabled?(:admin_feature, regular)).to be false
      end

      it "disables for a group" do
        Flagstack.enable_group(:admin_feature, :admins)
        Flagstack.disable_group(:admin_feature, :admins)
        expect(Flagstack.enabled?(:admin_feature, admin)).to be false
      end
    end

    describe ".enable_percentage_of_actors" do
      let(:user) { double("User", flipper_id: "User_test") }

      it "enables for a percentage of actors" do
        Flagstack.enable_percentage_of_actors(:percentage_feature_test, 100)
        expect(Flagstack.enabled?(:percentage_feature_test, user)).to be true
      end

      it "is deterministic for same actor" do
        Flagstack.enable_percentage_of_actors(:pct_feature, 50)
        results = 10.times.map { Flagstack.enabled?(:pct_feature, user) }
        expect(results.uniq.size).to eq(1)
      end
    end

    describe ".[]" do
      it "returns a feature object" do
        feature = Flagstack[:new_checkout]
        expect(feature).to respond_to(:enabled?)
        expect(feature.enabled?).to be true
      end

      it "allows chaining feature methods" do
        Flagstack[:chain_feature].enable
        expect(Flagstack[:chain_feature].enabled?).to be true
      end
    end

    describe ".features" do
      it "returns list of features" do
        features = Flagstack.features
        expect(features.map(&:key)).to include("new_checkout", "beta_feature")
      end

      it "returns empty array when not configured" do
        Flagstack.reset!
        expect(Flagstack.features).to eq([])
      end
    end

    describe ".register" do
      it "registers a group" do
        Flagstack.register(:test_group) { |actor| true }
        expect(Flipper.groups.map(&:name)).to include(:test_group)
      end
    end
  end
end

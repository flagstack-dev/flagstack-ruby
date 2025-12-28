require "spec_helper"

RSpec.describe Flagstack::Client do
  let(:config) do
    Flagstack::Configuration.new(
      token: "fs_live_test",
      url: "https://flagstack.io"
    )
  end
  let(:client) { described_class.new(config) }

  describe "#sync" do
    context "with successful response" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/sync")
          .to_return(
            status: 200,
            body: { "features" => [], "synced_at" => "2024-01-01" }.to_json,
            headers: { "ETag" => "abc123" }
          )
      end

      it "returns parsed JSON" do
        result = client.sync
        expect(result).to be_a(Hash)
        expect(result["features"]).to eq([])
      end

      it "sends authorization header" do
        client.sync
        expect(a_request(:get, "https://flagstack.io/api/v1/sync")
          .with(headers: { "Authorization" => "Bearer fs_live_test" }))
          .to have_been_made
      end
    end

    context "with 304 response (not modified)" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/sync")
          .to_return(status: 200, body: { "features" => [] }.to_json, headers: { "ETag" => "abc123" })
          .then
          .to_return(status: 304)
      end

      it "returns nil" do
        client.sync # first request sets ETag
        expect(client.sync).to be_nil
      end
    end

    context "with 401 response" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/sync")
          .to_return(status: 401, body: "Unauthorized")
      end

      it "raises APIError" do
        expect { client.sync }.to raise_error(Flagstack::APIError, "Invalid API token")
      end
    end

    context "with 429 response (rate limited)" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/sync")
          .to_return(status: 429)
      end

      it "returns nil" do
        expect(client.sync).to be_nil
      end
    end

    context "with timeout" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/sync")
          .to_timeout
      end

      it "returns nil" do
        expect(client.sync).to be_nil
      end
    end
  end

  describe "#check" do
    before do
      stub_request(:get, "https://flagstack.io/api/v1/features/my_feature/check")
        .to_return(
          status: 200,
          body: { "feature" => "my_feature", "enabled" => true }.to_json
        )
    end

    it "returns enabled status" do
      expect(client.check("my_feature")).to be true
    end

    context "with actor_id" do
      before do
        stub_request(:get, "https://flagstack.io/api/v1/features/my_feature/check?actor_id=user_123")
          .to_return(
            status: 200,
            body: { "feature" => "my_feature", "enabled" => true }.to_json
          )
      end

      it "includes actor_id in query" do
        client.check("my_feature", actor_id: "user_123")
        expect(a_request(:get, "https://flagstack.io/api/v1/features/my_feature/check?actor_id=user_123"))
          .to have_been_made
      end
    end
  end
end

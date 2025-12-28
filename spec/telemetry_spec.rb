require "spec_helper"

RSpec.describe Flagstack::Telemetry do
  let(:config) do
    Flagstack::Configuration.new(
      token: "fs_live_test",
      telemetry_enabled: true,
      telemetry_interval: 60
    )
  end
  let(:client) { Flagstack::Client.new(config) }
  let(:telemetry) { described_class.new(client, config) }

  before do
    stub_request(:post, "https://flagstack.io/api/v1/telemetry")
      .to_return(status: 202, body: "", headers: { "Telemetry-Interval" => "60" })
  end

  describe "#record" do
    it "stores metrics when telemetry is enabled" do
      telemetry.record("test_feature", true)
      expect(telemetry.storage.size).to eq(1)
    end

    it "does not store metrics when telemetry is disabled" do
      disabled_config = Flagstack::Configuration.new(
        token: "fs_live_test",
        telemetry_enabled: false
      )
      disabled_telemetry = described_class.new(client, disabled_config)

      disabled_telemetry.record("test_feature", true)
      expect(disabled_telemetry.storage.size).to eq(0)
    end

    it "aggregates multiple checks of same feature" do
      3.times { telemetry.record("test_feature", true) }
      2.times { telemetry.record("test_feature", false) }

      expect(telemetry.storage.size).to eq(2) # One for true, one for false
    end
  end

  describe "#start and #stop" do
    it "starts and stops the telemetry timer" do
      expect(telemetry.running?).to be false

      telemetry.start
      expect(telemetry.running?).to be true

      telemetry.stop
      expect(telemetry.running?).to be false
    end

    it "does not start twice" do
      telemetry.start
      telemetry.start # Should not raise

      expect(telemetry.running?).to be true
      telemetry.stop
    end
  end

  describe "#flush" do
    it "drains the storage" do
      telemetry.record("test_feature", true)
      expect(telemetry.storage.size).to eq(1)

      telemetry.flush
      sleep 0.1 # Allow background thread to run

      expect(telemetry.storage.size).to eq(0)
    end

    it "does nothing when storage is empty" do
      expect { telemetry.flush }.not_to raise_error
    end
  end
end

RSpec.describe Flagstack::Telemetry::Metric do
  describe "#initialize" do
    it "creates a metric with key and result" do
      metric = described_class.new("test_feature", true)

      expect(metric.key).to eq("test_feature")
      expect(metric.result).to be true
      expect(metric.time).to be_a(Integer)
    end

    it "rounds time to the minute" do
      time1 = Time.new(2024, 1, 1, 12, 30, 15)
      time2 = Time.new(2024, 1, 1, 12, 30, 45)

      metric1 = described_class.new("test", true, time1)
      metric2 = described_class.new("test", true, time2)

      expect(metric1.time).to eq(metric2.time)
      # Time is stored as integer (seconds since epoch, rounded to minute)
      expect(metric1.time % 60).to eq(0)
    end
  end

  describe "#hash and #eql?" do
    it "creates a unique hash for aggregation" do
      metric = described_class.new("test_feature", true)
      expect(metric.hash).to be_a(Integer)
    end

    it "differentiates between true and false results" do
      true_metric = described_class.new("test_feature", true)
      false_metric = described_class.new("test_feature", false)

      expect(true_metric.hash).not_to eq(false_metric.hash)
      expect(true_metric).not_to eq(false_metric)
    end

    it "treats equivalent metrics as equal" do
      time = Time.now
      metric1 = described_class.new("test_feature", true, time)
      metric2 = described_class.new("test_feature", true, time)

      expect(metric1).to eq(metric2)
      expect(metric1.hash).to eq(metric2.hash)
    end
  end

  describe "#as_json" do
    it "returns a hash representation" do
      metric = described_class.new("test_feature", true)

      json = metric.as_json
      expect(json["key"]).to eq("test_feature")
      expect(json["result"]).to be true
      expect(json["time"]).to be_a(Integer)
    end
  end
end

RSpec.describe Flagstack::Telemetry::MetricStorage do
  let(:storage) { described_class.new }

  describe "#increment" do
    it "increments count for a metric" do
      metric = Flagstack::Telemetry::Metric.new("test_feature", true)

      storage.increment(metric)
      storage.increment(metric)
      storage.increment(metric)

      expect(storage.size).to eq(1)
    end
  end

  describe "#drain" do
    it "returns all metrics and clears storage" do
      storage.increment(Flagstack::Telemetry::Metric.new("feature1", true))
      storage.increment(Flagstack::Telemetry::Metric.new("feature2", false))

      metrics = storage.drain

      expect(metrics.size).to eq(2)
      expect(storage.size).to eq(0)
    end
  end

  describe "#empty?" do
    it "returns true when empty" do
      expect(storage.empty?).to be true
    end

    it "returns false when has metrics" do
      storage.increment(Flagstack::Telemetry::Metric.new("test", true))
      expect(storage.empty?).to be false
    end
  end

  describe "#size" do
    it "returns the number of unique metric buckets" do
      storage.increment(Flagstack::Telemetry::Metric.new("feature1", true))
      storage.increment(Flagstack::Telemetry::Metric.new("feature1", true))
      storage.increment(Flagstack::Telemetry::Metric.new("feature2", true))

      expect(storage.size).to eq(2)
    end
  end
end

RSpec.describe Flagstack::Telemetry::Submitter do
  let(:config) do
    Flagstack::Configuration.new(
      token: "fs_live_test",
      telemetry_enabled: true
    )
  end
  let(:client) { Flagstack::Client.new(config) }
  let(:submitter) { described_class.new(client, config) }

  before do
    stub_request(:post, "https://flagstack.io/api/v1/telemetry")
      .to_return(status: 202, body: "", headers: { "Telemetry-Interval" => "120" })
  end

  describe "#call" do
    it "submits metrics to the server" do
      # Metrics format from MetricStorage#drain: { Metric => count }
      metric1 = Flagstack::Telemetry::Metric.new("feature1", true)
      metric2 = Flagstack::Telemetry::Metric.new("feature2", false)
      metrics = { metric1 => 5, metric2 => 3 }

      submitter.call(metrics)

      expect(WebMock).to have_requested(:post, "https://flagstack.io/api/v1/telemetry")
    end

    it "updates telemetry interval from response header" do
      metric = Flagstack::Telemetry::Metric.new("feature1", true)
      metrics = { metric => 1 }

      submitter.call(metrics)

      expect(config.telemetry_interval).to eq(120)
    end

    it "does nothing when metrics are empty" do
      submitter.call({})

      expect(WebMock).not_to have_requested(:post, "https://flagstack.io/api/v1/telemetry")
    end
  end
end

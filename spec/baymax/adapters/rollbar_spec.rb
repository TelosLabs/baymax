# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::Adapters::Rollbar do
  let(:payload) { JSON.parse(File.read("spec/fixtures/payloads/rollbar_webhook.json")) }
  let(:adapter) { described_class.new }

  describe ".matches?" do
    it "returns true for rollbar payloads" do
      expect(described_class.matches?(payload)).to be true
    end

    it "returns false for appsignal payloads" do
      expect(described_class.matches?("source" => "appsignal")).to be false
    end

    it "returns false for unknown payloads" do
      expect(described_class.matches?("source" => "datadog")).to be false
    end
  end

  describe "#normalize_webhook" do
    subject(:alert) { adapter.normalize_webhook(payload) }

    it "returns an Alert struct" do
      expect(alert).to be_a(Telos::AgentToolkit::Alert)
    end

    it "extracts all fields" do
      expect(alert.source).to eq("rollbar")
      expect(alert.error_class).to eq("ActiveRecord::RecordNotFound")
      expect(alert.error_message).to eq("Couldn't find User with id=999")
      expect(alert.severity).to eq(:error)
      expect(alert.occurrence_count).to eq(5)
      expect(alert.revision).to eq("def789abc012")
      expect(alert.app_name).to eq("astro-production")
      expect(alert.incident_id).to eq("67890")
      expect(alert.raw_payload).to eq(payload)
    end

    it "handles missing fields with defaults" do
      minimal = { "source" => "rollbar" }
      alert = adapter.normalize_webhook(minimal)

      expect(alert.error_class).to eq("Unknown")
      expect(alert.error_message).to eq("")
      expect(alert.severity).to eq(:info)
      expect(alert.occurrence_count).to eq(0)
    end

    it "truncates error_message to 500 chars" do
      long_payload = payload.merge("error_message" => "x" * 600)
      alert = adapter.normalize_webhook(long_payload)

      expect(alert.error_message.length).to eq(500)
    end

    it "normalizes severity strings to symbols" do
      %w[error Error ERROR].each do |sev|
        alert = adapter.normalize_webhook(payload.merge("severity" => sev))
        expect(alert.severity).to eq(:error)
      end
    end

    it "maps warn to warning" do
      alert = adapter.normalize_webhook(payload.merge("severity" => "warn"))
      expect(alert.severity).to eq(:warning)
    end
  end

  describe "#fetch_full_details" do
    let(:alert) do
      adapter.normalize_webhook(payload)
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ROLLBAR_API_TOKEN").and_return("test-token")
    end

    it "retries on failure and returns enriched alert on success" do
      stub_request(:get, %r{api.rollbar.com/api/1/item/67890})
        .to_return(
          { status: 500, body: "error" },
          { status: 200, body: { "result" => { "title" => "enriched title", "total_occurrences" => 50 } }.to_json,
            headers: { "Content-Type" => "application/json" } }
        )

      allow(adapter).to receive(:sleep)

      result = adapter.fetch_full_details(alert)
      expect(result.error_message).to eq("enriched title")
      expect(result.occurrence_count).to eq(50)
    end

    it "returns degraded alert on persistent failure" do
      stub_request(:get, %r{api.rollbar.com/api/1/item/67890})
        .to_return(status: 500, body: "error")

      allow(adapter).to receive(:sleep)

      result = adapter.fetch_full_details(alert)
      expect(result).to eq(alert)
    end
  end
end

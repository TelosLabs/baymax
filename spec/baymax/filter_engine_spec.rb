# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::FilterEngine do
  let(:config) do
    Telos::AgentToolkit::Config.new({
      "llm" => { "provider" => "anthropic", "model" => "claude-sonnet-4-5-20250514" },
      "github" => { "repo" => "TelosLabs/astro" },
      "filter" => { "min_severity" => "warning", "min_occurrences" => 5, "ignored_error_classes" => ["SignalException"] }
    })
  end

  let(:engine) { described_class.new(config) }

  def build_alert(overrides = {})
    defaults = {
      source: "appsignal",
      error_class: "NoMethodError",
      error_message: "undefined method 'foo'",
      severity: :error,
      occurrence_count: 10,
      revision: "abc123",
      app_name: "astro-production",
      incident_id: "12345",
      raw_payload: {}
    }
    Telos::AgentToolkit::Alert.new(**defaults.merge(overrides))
  end

  describe "#evaluate" do
    it "passes alert meeting all criteria" do
      result = engine.evaluate(build_alert)

      expect(result[:pass]).to be true
      expect(result[:reason]).to include("meets all filter criteria")
    end

    it "rejects below severity threshold" do
      result = engine.evaluate(build_alert(severity: :info))

      expect(result[:pass]).to be false
      expect(result[:reason]).to include("severity")
    end

    it "rejects below occurrence count" do
      result = engine.evaluate(build_alert(occurrence_count: 2))

      expect(result[:pass]).to be false
      expect(result[:reason]).to include("occurrence count")
    end

    it "rejects ignored error classes" do
      result = engine.evaluate(build_alert(error_class: "SignalException"))

      expect(result[:pass]).to be false
      expect(result[:reason]).to include("ignored error class")
    end

    it "handles nil severity by treating as :info" do
      result = engine.evaluate(build_alert(severity: nil))

      expect(result[:pass]).to be false
      expect(result[:reason]).to include("severity")
    end

    it "handles nil occurrence_count by treating as 1" do
      result = engine.evaluate(build_alert(occurrence_count: nil))

      expect(result[:pass]).to be false
      expect(result[:reason]).to include("occurrence count")
    end

    it "passes alert at exactly minimum severity" do
      result = engine.evaluate(build_alert(severity: :warning))

      expect(result[:pass]).to be true
    end

    it "passes alert at exactly minimum occurrences" do
      result = engine.evaluate(build_alert(occurrence_count: 5))

      expect(result[:pass]).to be true
    end
  end
end

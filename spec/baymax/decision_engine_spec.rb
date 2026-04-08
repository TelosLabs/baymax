# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::DecisionEngine do
  let(:config) do
    Telos::AgentToolkit::Config.new({
      "llm" => { "provider" => "anthropic", "model" => "claude-sonnet-4-6" },
      "github" => { "repo" => "TelosLabs/astro" },
      "decision" => { "confidence_threshold" => 0.7 }
    })
  end

  let(:engine) { described_class.new(config) }

  def build_triage(overrides = {})
    defaults = {
      root_cause: "Missing nil check",
      confidence: 0.85,
      security_tier: :tier_one,
      fixable: true,
      affected_files: ["app/models/user.rb"],
      suggested_fix: "Add nil guard",
      data_related: false,
      category: :code_bug
    }
    Telos::AgentToolkit::TriageResult.new(**defaults.merge(overrides))
  end

  describe "#decide" do
    it "returns :skip for duplicate alerts" do
      result = engine.decide(triage_result: build_triage, duplicate: true)

      expect(result.action).to eq(:skip)
      expect(result.reason).to include("Duplicate")
    end

    it "returns :queued when rate limited" do
      result = engine.decide(triage_result: build_triage, rate_limited: true)

      expect(result.action).to eq(:queued)
      expect(result.labels).to include("baymax-queued")
    end

    it "returns :diagnosis_only for data-related errors" do
      triage = build_triage(data_related: true)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:diagnosis_only)
      expect(result.reason).to include("Data-related")
    end

    it "returns :diagnosis_only with urgent for tier_three" do
      triage = build_triage(security_tier: :tier_three)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:diagnosis_only)
      expect(result.urgent).to be true
      expect(result.labels).to include("urgent")
    end

    it "returns :fix_with_review for tier_two + fixable + confident" do
      triage = build_triage(security_tier: :tier_two)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:fix_with_review)
      expect(result.labels).to include("baymax-fix", "review-required")
    end

    it "returns :fix for tier_one + fixable + confident" do
      result = engine.decide(triage_result: build_triage)

      expect(result.action).to eq(:fix)
      expect(result.labels).to include("baymax-fix")
    end

    it "returns :diagnosis_only for non-fixable alerts" do
      triage = build_triage(fixable: false)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:diagnosis_only)
      expect(result.reason).to include("Not auto-fixable")
    end

    it "returns :diagnosis_only for low confidence" do
      triage = build_triage(confidence: 0.3)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:diagnosis_only)
      expect(result.reason).to include("Low confidence")
      expect(result.reason).to include("30%")
    end

    it "returns :fix when confidence is exactly at threshold (boundary)" do
      triage = build_triage(confidence: 0.7)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:fix)
    end

    it "returns :diagnosis_only when confidence is just below threshold" do
      triage = build_triage(confidence: 0.69)
      result = engine.decide(triage_result: triage)

      expect(result.action).to eq(:diagnosis_only)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::Triage do
  let(:config) do
    Telos::AgentToolkit::Config.new({
      "llm" => { "provider" => "anthropic", "model" => "claude-sonnet-4-6" },
      "github" => { "repo" => "TelosLabs/astro" }
    })
  end

  let(:llm_client) { instance_double(Telos::AgentToolkit::LlmClient) }
  let(:triage) { described_class.new(config) }

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

  before do
    allow(Telos::AgentToolkit::LlmClient).to receive(:new).and_return(llm_client)
  end

  describe "#call" do
    let(:llm_response) do
      {
        "root_cause" => "Missing nil check on user association",
        "confidence" => 0.85,
        "security_tier" => "tier_one",
        "fixable" => true,
        "affected_files" => ["app/models/user.rb"],
        "suggested_fix" => "Add nil guard before calling method",
        "data_related" => false,
        "category" => "code_bug"
      }
    end

    it "returns valid TriageResult from LLM response" do
      allow(llm_client).to receive(:chat_json).and_return(llm_response)

      result = triage.call(alert: build_alert)

      expect(result).to be_a(Telos::AgentToolkit::TriageResult)
      expect(result.root_cause).to eq("Missing nil check on user association")
      expect(result.confidence).to eq(0.85)
      expect(result.security_tier).to eq(:tier_one)
      expect(result.fixable).to be true
      expect(result.affected_files).to eq(["app/models/user.rb"])
      expect(result.category).to eq(:code_bug)
    end

    it "handles LLM timeout and returns degraded result" do
      allow(llm_client).to receive(:chat_json)
        .and_raise(Telos::AgentToolkit::LlmClient::TimeoutError, "timeout")

      result = triage.call(alert: build_alert)

      expect(result.confidence).to eq(0.0)
      expect(result.fixable).to be false
      expect(result.root_cause).to include("unavailable")
    end

    it "handles LLM error and returns degraded result" do
      allow(llm_client).to receive(:chat_json)
        .and_raise(Telos::AgentToolkit::LlmClient::Error, "parse failed")

      result = triage.call(alert: build_alert)

      expect(result.confidence).to eq(0.0)
      expect(result.fixable).to be false
      expect(result.security_tier).to eq(:tier_one)
    end

    it "merges security scanner override to tier_three and fixable=false" do
      allow(llm_client).to receive(:chat_json).and_return(llm_response)
      override = { tier: :tier_three, matched_keywords: ["password"] }

      result = triage.call(alert: build_alert, security_override: override)

      expect(result.security_tier).to eq(:tier_three)
      expect(result.fixable).to be false
      expect(result.root_cause).to eq("Missing nil check on user association")
    end

    it "applies security override even on LLM failure" do
      allow(llm_client).to receive(:chat_json)
        .and_raise(Telos::AgentToolkit::LlmClient::Error, "fail")
      override = { tier: :tier_three, matched_keywords: ["token"] }

      result = triage.call(alert: build_alert, security_override: override)

      expect(result.security_tier).to eq(:tier_three)
    end

    it "clamps confidence to 0.0-1.0" do
      allow(llm_client).to receive(:chat_json)
        .and_return(llm_response.merge("confidence" => 1.5))

      result = triage.call(alert: build_alert)

      expect(result.confidence).to eq(1.0)
    end

    it "clamps negative confidence to 0.0" do
      allow(llm_client).to receive(:chat_json)
        .and_return(llm_response.merge("confidence" => -0.5))

      result = triage.call(alert: build_alert)

      expect(result.confidence).to eq(0.0)
    end

    context "with custom prompt path" do
      it "loads system prompt from file" do
        prompt_file = Tempfile.new("baymax-prompt")
        prompt_file.write("Custom system prompt for triage")
        prompt_file.close

        custom_triage = described_class.new(config, prompt_path: prompt_file.path)
        allow(llm_client).to receive(:chat_json).and_return(llm_response)

        result = custom_triage.call(alert: build_alert)

        expect(result).to be_a(Telos::AgentToolkit::TriageResult)
        expect(llm_client).to have_received(:chat_json) do |args|
          system_msg = args[:messages].find { |m| m[:role] == "system" }
          expect(system_msg[:content]).to eq("Custom system prompt for triage")
        end

        prompt_file.unlink
      end
    end
  end
end

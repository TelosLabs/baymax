# frozen_string_literal: true

module Baymax
  class Triage
    DEFAULT_PROMPT = <<~PROMPT
      You are a production error triage assistant. Analyze the error and provide a structured diagnosis.

      Respond with JSON:
      {
        "root_cause": "Description of the root cause",
        "confidence": 0.85,
        "security_tier": "tier_one",
        "fixable": true,
        "affected_files": ["app/models/user.rb"],
        "suggested_fix": "Description of the fix",
        "data_related": false,
        "category": "code_bug"
      }

      Security tiers: tier_one (safe), tier_two (review required), tier_three (human-only)
      Categories: code_bug, config, dependency, infra, data
      Confidence: 0.0 to 1.0
    PROMPT

    VALID_TIERS = %i[tier_one tier_two tier_three].freeze

    def initialize(config, prompt_path: nil)
      @config = config
      @llm = Telos::AgentToolkit::LlmClient.new(config)
      @prompt_path = prompt_path
    end

    def call(alert:, context: {}, security_override: nil)
      result = run_llm_triage(alert, context)
      apply_security_override(result, security_override)
    rescue Telos::AgentToolkit::LlmClient::Error,
           Telos::AgentToolkit::LlmClient::TimeoutError => e
      warn "[baymax] LLM triage failed: #{e.message}. Returning degraded result."
      degraded_result(security_override)
    end

    private

    def run_llm_triage(alert, context)
      response = @llm.chat_json(messages: [
                                  { role: 'system', content: system_prompt },
                                  { role: 'user', content: user_prompt(alert, context) }
                                ])
      parse_response(response)
    end

    def system_prompt
      @prompt_path && File.exist?(@prompt_path) ? File.read(@prompt_path) : DEFAULT_PROMPT
    end

    def user_prompt(alert, context)
      parts = alert_details(alert)
      append_context(parts, context)
      parts.join("\n")
    end

    def alert_details(alert)
      parts = ['## Error Details']
      parts << "- **Class:** #{alert.error_class}"
      parts << "- **Message:** #{alert.error_message}"
      parts << "- **Severity:** #{alert.severity}"
      parts << "- **Source:** #{alert.source}"
      parts << "- **Occurrences:** #{alert.occurrence_count}"
      parts << "- **Revision:** #{alert.revision}" unless alert.revision.to_s.empty?
      parts
    end

    def append_context(parts, context)
      { '## Source Code at Revision' => :source_at_revision,
        '## Git Blame' => :blame,
        '## Recent Commits' => :recent_commits }.each do |heading, key|
        next unless context[key]

        parts << "\n#{heading}"
        parts << context[key]
      end
    end

    def parse_response(response)
      Telos::AgentToolkit::TriageResult.new(
        root_cause: response['root_cause'] || 'Unknown',
        confidence: (response['confidence'] || 0.0).to_f.clamp(0.0, 1.0),
        security_tier: parse_tier(response['security_tier']),
        fixable: response['fixable'] == true,
        affected_files: Array(response['affected_files']),
        suggested_fix: response['suggested_fix'],
        data_related: response['data_related'] == true,
        category: (response['category'] || 'code_bug').to_sym
      )
    end

    def parse_tier(raw)
      sym = (raw || 'tier_one').to_sym
      VALID_TIERS.include?(sym) ? sym : :tier_one
    end

    def apply_security_override(result, override)
      return result unless override

      Telos::AgentToolkit::TriageResult.new(
        root_cause: result.root_cause, confidence: result.confidence,
        security_tier: :tier_three, fixable: false,
        affected_files: result.affected_files, suggested_fix: result.suggested_fix,
        data_related: result.data_related, category: result.category
      )
    end

    def degraded_result(security_override)
      Telos::AgentToolkit::TriageResult.new(
        root_cause: 'LLM triage unavailable — manual review required',
        confidence: 0.0, security_tier: security_override ? :tier_three : :tier_one,
        fixable: false, affected_files: [], suggested_fix: nil,
        data_related: false, category: :code_bug
      )
    end
  end
end

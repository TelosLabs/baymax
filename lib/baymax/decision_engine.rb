# frozen_string_literal: true

module Baymax
  class DecisionEngine
    DEFAULT_CONFIDENCE_THRESHOLD = 0.7

    def initialize(config)
      @confidence_threshold = config_threshold(config)
    end

    def decide(triage_result:, duplicate: false, rate_limited: false)
      early = check_preconditions(duplicate, rate_limited, triage_result)
      return early if early

      evaluate_fix(triage_result)
    end

    private

    def config_threshold(config)
      (config.raw.dig('decision', 'confidence_threshold') || DEFAULT_CONFIDENCE_THRESHOLD).to_f
    end

    def check_preconditions(duplicate, rate_limited, triage_result)
      return skip('Duplicate alert — existing issue found') if duplicate
      return queued('Rate limit exceeded — triage queued') if rate_limited
      return diagnosis_only('Data-related error — requires human review') if triage_result.data_related

      urgent_review('Security tier 3 — human review required') if triage_result.security_tier == :tier_three
    end

    def evaluate_fix(triage_result)
      return diagnosis_only(low_confidence_reason(triage_result)) unless confident?(triage_result)
      return diagnosis_only('Not auto-fixable') unless triage_result.fixable

      tier_two?(triage_result) ? fix_with_review : fix
    end

    def confident?(triage_result)
      triage_result.confidence >= @confidence_threshold
    end

    def tier_two?(triage_result)
      triage_result.security_tier == :tier_two
    end

    def low_confidence_reason(triage_result)
      pct = (triage_result.confidence * 100).round
      "Low confidence (#{pct}%) — manual review needed"
    end

    def skip(reason)
      build_decision(action: :skip, reason: reason)
    end

    def queued(reason)
      build_decision(action: :queued, reason: reason, labels: ['baymax-queued'])
    end

    def diagnosis_only(reason)
      build_decision(action: :diagnosis_only, reason: reason)
    end

    def urgent_review(reason)
      build_decision(action: :diagnosis_only, reason: reason, urgent: true, labels: ['urgent'])
    end

    def fix_with_review
      build_decision(
        action: :fix_with_review,
        reason: 'Tier 2 — confident and fixable, but requires review',
        labels: %w[baymax-fix review-required]
      )
    end

    def fix
      build_decision(
        action: :fix,
        reason: 'Tier 1 — confident and fixable, dispatching agent',
        labels: ['baymax-fix']
      )
    end

    def build_decision(action:, reason:, urgent: false, labels: [])
      Telos::AgentToolkit::Decision.new(
        action: action, reason: reason, urgent: urgent, labels: labels
      )
    end
  end
end

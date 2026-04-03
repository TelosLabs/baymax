# frozen_string_literal: true

module Baymax
  class Analyzer
    module PipelineSteps
      private

      def log(message)
        puts "[baymax] #{message}"
      end

      def detect_and_normalize(payload)
        adapter = Baymax::Adapters::Base.detect(payload)
        alert = adapter.normalize_webhook(payload)
        log "Adapter: #{adapter.class.name}, Alert: #{alert.error_class}"
        alert
      end

      def passes_filter?(alert)
        result = FilterEngine.new(@config).evaluate(alert)
        return true if result[:pass]

        log "Filtered: #{result[:reason]}"
        @last_filter_reason = result[:reason]
        false
      end

      def filter_result(alert)
        summary(:filtered, alert: alert, reason: @last_filter_reason)
      end

      def generate_fingerprint(alert)
        Telos::AgentToolkit::Fingerprint.generate(
          source: alert.source, error_class: alert.error_class, app_name: alert.app_name
        )
      end

      def find_duplicate(fingerprint, dry_run)
        return nil if dry_run

        client = Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN', ''))
        Telos::AgentToolkit::Fingerprint.duplicate?(
          client: client, repo: @config.github_repo, fingerprint: fingerprint
        )
      end

      def rate_limited?(dry_run)
        return false if dry_run

        max = @config.raw.dig('triage', 'max_triage_per_hour')
        return false unless max

        Telos::AgentToolkit::IssueManager.new(@config).rate_limited?(max.to_i)
      end

      def security_scan(alert)
        SecurityScanner.new.scan(alert)
      end

      def log_security(result)
        msg = result ? "tier_3 forced (#{result[:matched_keywords].join(', ')})" : 'clear'
        log "Security scan: #{msg}"
      end

      def resolve_triage(alert, security_result, skip_llm)
        if skip_llm
          skip_llm_triage(security_result)
        else
          context = ContextGatherer.new.gather(alert)
          run_triage(alert, context, security_result)
        end
      end

      def run_triage(alert, context, security_override)
        Triage.new(@config, prompt_path: @prompt_path).call(
          alert: alert, context: context, security_override: security_override
        )
      end

      def skip_llm_triage(security_override)
        tier = security_override ? :tier_three : :tier_one
        Telos::AgentToolkit::TriageResult.new(
          root_cause: 'LLM skipped — filter-only data',
          confidence: 0.0, security_tier: tier, fixable: false,
          affected_files: [], suggested_fix: nil,
          data_related: false, category: :code_bug
        )
      end

      def log_triage(result)
        pct = (result.confidence * 100).round
        log "Triage: confidence=#{pct}%, tier=#{result.security_tier}, fixable=#{result.fixable}"
      end

      def decide(triage_result:, duplicate:, rate_limited:)
        DecisionEngine.new(@config).decide(
          triage_result: triage_result, duplicate: duplicate, rate_limited: rate_limited
        )
      end

      def finalize(alert, triage_result, decision, fingerprint, dry_run)
        issue_result = create_issue(alert, triage_result, decision, fingerprint, dry_run)
        log "Issue: #{issue_result[:status]}"

        maybe_assign_agent(issue_result, alert, triage_result, decision, dry_run)
        summary(:completed, alert: alert, decision: decision, issue: issue_result)
      end

      def create_issue(alert, triage_result, decision, fingerprint, dry_run)
        if dry_run
          log "[DRY RUN] Would create issue: #{alert.error_class}"
          return { status: :dry_run }
        end

        Telos::AgentToolkit::IssueManager.new(@config).create_issue(
          alert: alert, triage_result: triage_result, decision: decision, fingerprint: fingerprint
        )
      end

      def maybe_assign_agent(issue_result, alert, triage_result, decision, dry_run)
        return unless %i[fix fix_with_review].include?(decision.action)
        return unless issue_result[:status] == :created && !dry_run

        Telos::AgentToolkit::AgentAssigner.new(@config).assign(
          issue_number: issue_result[:issue].number, alert: alert, triage_result: triage_result
        )
        log "Agent assigned: #{@config.raw.dig('auto_assign', 'agent') || 'claude'}"
      end
    end
  end
end

# frozen_string_literal: true

require 'octokit'
require_relative 'analyzer/pipeline_steps'

module Baymax
  class Analyzer
    include PipelineSteps

    def initialize(config, prompt_path: nil)
      @config = config
      @prompt_path = prompt_path
    end

    def run(event_payload:, dry_run: false, skip_llm: false)
      log 'Starting Baymax triage pipeline'
      execute_pipeline(event_payload, dry_run, skip_llm)
    rescue ArgumentError => e
      log "Adapter error: #{e.message}"
      summary(:error, reason: e.message)
    rescue StandardError => e
      log "Pipeline error: #{e.class} — #{e.message}"
      summary(:error, reason: "#{e.class}: #{e.message}")
    end

    private

    def execute_pipeline(payload, dry_run, skip_llm)
      alert = detect_and_normalize(payload)
      return filter_result(alert) unless passes_filter?(alert)

      pipeline_data = gather_pipeline_data(alert, dry_run, skip_llm)
      decision = decide(**pipeline_data.slice(:triage_result, :duplicate, :rate_limited))
      log "Decision: #{decision.action} — #{decision.reason}"

      return summary(:skip, alert: alert, decision: decision) if decision.action == :skip

      finalize(alert, pipeline_data[:triage_result], decision, pipeline_data[:fingerprint], dry_run)
    end

    def gather_pipeline_data(alert, dry_run, skip_llm)
      fingerprint = generate_fingerprint(alert)
      duplicate = find_duplicate(fingerprint, dry_run)
      log "Fingerprint: #{fingerprint[0..7]}... Duplicate: #{!duplicate.nil?}"

      rate_limited = rate_limited?(dry_run)
      security_result = security_scan(alert)
      log_security(security_result)

      triage_result = resolve_triage(alert, security_result, skip_llm)
      log_triage(triage_result)

      { fingerprint: fingerprint, duplicate: !duplicate.nil?,
        rate_limited: rate_limited, triage_result: triage_result }
    end

    def summary(status, alert: nil, decision: nil, issue: nil, reason: nil)
      result = { status: status }
      result[:error_class] = alert.error_class if alert
      result[:decision] = decision.action if decision
      result[:reason] = reason || decision&.reason
      result[:issue] = issue if issue
      result
    end
  end
end

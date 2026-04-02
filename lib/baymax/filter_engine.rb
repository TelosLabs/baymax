# frozen_string_literal: true

module Baymax
  class FilterEngine
    SEVERITY_RANKS = {
      info: 0,
      warning: 1,
      error: 2,
      critical: 3
    }.freeze

    def initialize(config)
      filter = config.raw.fetch('filter', {})
      @min_severity = filter.fetch('min_severity', 'info').to_sym
      @min_occurrences = filter.fetch('min_occurrences', 1).to_i
      @ignored_error_classes = Array(filter.fetch('ignored_error_classes', []))
    end

    def evaluate(alert)
      return reject("ignored error class: #{alert.error_class}") if ignored?(alert)
      return reject("severity #{alert_severity(alert)} below minimum #{@min_severity}") if below_severity?(alert)
      if below_occurrences?(alert)
        return reject("occurrence count #{alert_occurrences(alert)} below minimum #{@min_occurrences}")
      end

      { pass: true, reason: 'alert meets all filter criteria' }
    end

    private

    def ignored?(alert)
      @ignored_error_classes.include?(alert.error_class)
    end

    def below_severity?(alert)
      rank(alert_severity(alert)) < rank(@min_severity)
    end

    def below_occurrences?(alert)
      alert_occurrences(alert) < @min_occurrences
    end

    def alert_severity(alert)
      alert.severity || :info
    end

    def alert_occurrences(alert)
      alert.occurrence_count || 1
    end

    def rank(severity)
      SEVERITY_RANKS.fetch(severity.to_sym, 0)
    end

    def reject(reason)
      { pass: false, reason: reason }
    end
  end
end

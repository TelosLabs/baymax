# frozen_string_literal: true

module Baymax
  class SecurityScanner
    DANGER_KEYWORDS = %w[
      credential password secret pii token api_key
      private_key ssh bearer authorization
      credit_card ssn social_security
    ].freeze

    def scan(alert)
      text = "#{alert.error_class} #{alert.error_message}".downcase
      matched = DANGER_KEYWORDS.select { |kw| text.include?(kw) }
      return nil if matched.empty?

      { tier: :tier_three, matched_keywords: matched }
    end
  end
end

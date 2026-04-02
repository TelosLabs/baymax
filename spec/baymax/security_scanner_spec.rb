# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::SecurityScanner do
  subject(:scanner) { described_class.new }

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

  describe "#scan" do
    it "returns nil for non-security alerts" do
      alert = build_alert(error_class: "NoMethodError", error_message: "undefined method 'foo'")

      expect(scanner.scan(alert)).to be_nil
    end

    it "forces tier_three when 'password' appears in error message" do
      alert = build_alert(error_message: "invalid password reset token")
      result = scanner.scan(alert)

      expect(result[:tier]).to eq(:tier_three)
    end

    it "forces tier_three when 'credential' appears in error class" do
      alert = build_alert(error_class: "CredentialExpiredError")
      result = scanner.scan(alert)

      expect(result[:tier]).to eq(:tier_three)
    end

    it "forces tier_three when 'api_key' appears in error message" do
      alert = build_alert(error_message: "missing api_key in request")
      result = scanner.scan(alert)

      expect(result[:tier]).to eq(:tier_three)
    end

    it "returns matched keywords list" do
      alert = build_alert(error_message: "invalid password and token expired")
      result = scanner.scan(alert)

      expect(result[:matched_keywords]).to include("password", "token")
    end

    it "matches case-insensitively" do
      alert = build_alert(error_message: "Missing BEARER token")
      result = scanner.scan(alert)

      expect(result[:tier]).to eq(:tier_three)
      expect(result[:matched_keywords]).to include("bearer", "token")
    end
  end
end

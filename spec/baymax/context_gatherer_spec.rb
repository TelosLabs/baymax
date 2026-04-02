# frozen_string_literal: true

require "spec_helper"

RSpec.describe Baymax::ContextGatherer do
  subject(:gatherer) { described_class.new(repo_path: repo_path) }

  let(:repo_path) { "/tmp/baymax-test-repo" }

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

  describe "#gather" do
    it "returns hash with expected keys" do
      alert = build_alert

      # Stub git commands to avoid real git operations
      allow(gatherer).to receive(:system).and_return(false)
      allow(gatherer).to receive(:`).and_return("")

      result = gatherer.gather(alert)

      expect(result).to have_key(:revision)
      expect(result).to have_key(:source_at_revision)
      expect(result).to have_key(:blame)
      expect(result).to have_key(:recent_commits)
    end

    it "falls back to HEAD when revision is nil" do
      alert = build_alert(revision: nil)
      allow(gatherer).to receive(:`).and_return("")

      result = gatherer.gather(alert)

      expect(result[:revision]).to eq("HEAD")
    end

    it "falls back to HEAD when revision is empty" do
      alert = build_alert(revision: "")
      allow(gatherer).to receive(:`).and_return("")

      result = gatherer.gather(alert)

      expect(result[:revision]).to eq("HEAD")
    end

    it "handles errors gracefully and returns minimal context" do
      alert = build_alert
      allow(gatherer).to receive(:system).and_raise(StandardError, "git not found")

      result = gatherer.gather(alert)

      expect(result[:revision]).to eq("HEAD")
      expect(result[:source_at_revision]).to be_nil
      expect(result[:blame]).to be_nil
      expect(result[:recent_commits]).to be_nil
    end
  end
end

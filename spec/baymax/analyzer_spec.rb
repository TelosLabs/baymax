# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Baymax::Analyzer do
  let(:config) do
    Telos::AgentToolkit::Config.new({
      'llm' => { 'provider' => 'anthropic', 'model' => 'claude-sonnet-4-5-20250514' },
      'github' => { 'repo' => 'TelosLabs/astro' },
      'filter' => { 'min_severity' => 'error', 'min_occurrences' => 1 },
      'decision' => { 'confidence_threshold' => 0.7 },
      'triage' => { 'max_triage_per_hour' => 20 },
      'auto_assign' => { 'agent' => 'claude' }
    })
  end

  let(:payload) { JSON.parse(File.read(fixture_path('appsignal_webhook.json'))) }
  let(:analyzer) { described_class.new(config) }

  let(:triage_response) do
    {
      'root_cause' => 'Missing nil check on user association',
      'confidence' => 0.85,
      'security_tier' => 'tier_one',
      'fixable' => true,
      'affected_files' => ['app/models/user.rb'],
      'suggested_fix' => 'Add nil guard before calling name',
      'data_related' => false,
      'category' => 'code_bug'
    }
  end

  let(:mock_issue) { double('Issue', number: 1, html_url: 'https://github.com/TelosLabs/astro/issues/1') }

  def fixture_path(name)
    File.expand_path("../fixtures/payloads/#{name}", __dir__)
  end

  before do
    allow(Telos::AgentToolkit::Fingerprint).to receive(:duplicate?).and_return(nil)

    issue_manager = instance_double(Telos::AgentToolkit::IssueManager)
    allow(Telos::AgentToolkit::IssueManager).to receive(:new).and_return(issue_manager)
    allow(issue_manager).to receive(:rate_limited?).and_return(false)
    allow(issue_manager).to receive(:create_issue).and_return({ status: :created, issue: mock_issue })
    allow(issue_manager).to receive(:ensure_labels!).and_return(nil)

    agent_assigner = instance_double(Telos::AgentToolkit::AgentAssigner)
    allow(Telos::AgentToolkit::AgentAssigner).to receive(:new).and_return(agent_assigner)
    allow(agent_assigner).to receive(:assign).and_return(true)

    llm_client = instance_double(Telos::AgentToolkit::LlmClient)
    allow(Telos::AgentToolkit::LlmClient).to receive(:new).and_return(llm_client)
    allow(llm_client).to receive(:chat_json).and_return(triage_response)

    allow_any_instance_of(Baymax::ContextGatherer).to receive(:gather).and_return(
      { revision: 'HEAD', source_at_revision: nil, blame: nil, recent_commits: nil }
    )
  end

  describe '#run' do
    it 'completes full pipeline from webhook to issue creation' do
      result = analyzer.run(event_payload: payload)

      expect(result[:status]).to eq(:completed)
      expect(result[:error_class]).to eq('NoMethodError')
      expect(result[:decision]).to eq(:fix)
      expect(result[:issue][:status]).to eq(:created)
    end

    it 'filters alerts that do not meet criteria' do
      low_severity_payload = payload.merge('severity' => 'info')

      result = analyzer.run(event_payload: low_severity_payload)

      expect(result[:status]).to eq(:filtered)
      expect(result[:reason]).to include('severity')
    end

    it 'skips duplicate alerts' do
      allow(Telos::AgentToolkit::Fingerprint).to receive(:duplicate?).and_return(mock_issue)

      result = analyzer.run(event_payload: payload)

      expect(result[:status]).to eq(:skip)
      expect(result[:decision]).to eq(:skip)
      expect(result[:reason]).to include('Duplicate')
    end

    context 'with --dry-run' do
      it 'logs actions without GitHub API calls' do
        result = analyzer.run(event_payload: payload, dry_run: true, skip_llm: true)

        expect(result[:status]).to eq(:completed)
        expect(result[:issue][:status]).to eq(:dry_run)
      end

      it 'does not call Fingerprint.duplicate?' do
        analyzer.run(event_payload: payload, dry_run: true, skip_llm: true)

        expect(Telos::AgentToolkit::Fingerprint).not_to have_received(:duplicate?)
      end
    end

    context 'with --skip-llm' do
      it 'creates degraded triage result with zero confidence' do
        result = analyzer.run(event_payload: payload, dry_run: true, skip_llm: true)

        expect(result[:status]).to eq(:completed)
        expect(result[:decision]).to eq(:diagnosis_only)
      end
    end

    it 'queues when rate limited' do
      issue_manager = instance_double(Telos::AgentToolkit::IssueManager)
      allow(Telos::AgentToolkit::IssueManager).to receive(:new).and_return(issue_manager)
      allow(issue_manager).to receive(:rate_limited?).and_return(true)
      allow(issue_manager).to receive(:create_issue).and_return({ status: :created, issue: mock_issue })

      result = analyzer.run(event_payload: payload)

      expect(result[:status]).to eq(:completed)
      expect(result[:decision]).to eq(:queued)
    end

    it 'returns error for unknown payload format' do
      result = analyzer.run(event_payload: { 'source' => 'unknown_tool' })

      expect(result[:status]).to eq(:error)
      expect(result[:reason]).to include('No adapter found')
    end

    it 'returns correct summary statuses' do
      result = analyzer.run(event_payload: payload)

      expect(result).to include(:status, :error_class, :decision, :reason)
    end

    it 'assigns agent for :fix decisions with created issues' do
      analyzer.run(event_payload: payload)

      expect(Telos::AgentToolkit::AgentAssigner).to have_received(:new)
    end

    it 'does not assign agent for :diagnosis_only decisions' do
      llm = instance_double(Telos::AgentToolkit::LlmClient)
      allow(Telos::AgentToolkit::LlmClient).to receive(:new).and_return(llm)
      allow(llm).to receive(:chat_json).and_return(triage_response.merge('fixable' => false))

      assigner = instance_double(Telos::AgentToolkit::AgentAssigner)
      allow(Telos::AgentToolkit::AgentAssigner).to receive(:new).and_return(assigner)
      allow(assigner).to receive(:assign)

      analyzer.run(event_payload: payload)

      expect(assigner).not_to have_received(:assign)
    end
  end
end

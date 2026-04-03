# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "Baymax::Generators::InstallGenerator" do
  let(:template_dir) do
    File.expand_path(
      "../../../lib/generators/baymax/install/templates",
      __dir__
    )
  end

  let(:expected_templates) do
    %w[
      baymax_settings.yml
      baymax_triage.yml
      baymax_verify.yml
      baymax_triage.md
      baymax_diagnosis.md
      baymax_fix_instructions.md
    ]
  end

  describe "template files" do
    it "has all required template files" do
      expected_templates.each do |file|
        path = File.join(template_dir, file)
        expect(File.exist?(path)).to be(true), "Missing template: #{file}"
      end
    end
  end

  describe "baymax_settings.yml" do
    let(:content) { File.read(File.join(template_dir, "baymax_settings.yml")) }

    it "is valid YAML" do
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "contains required top-level keys" do
      config = YAML.safe_load(content)
      expect(config.keys).to include("llm", "github", "filter", "decision", "triage", "auto_assign")
    end

    it "sets a confidence threshold" do
      config = YAML.safe_load(content)
      expect(config.dig("decision", "confidence_threshold")).to eq(0.7)
    end
  end

  describe "baymax_triage.yml" do
    let(:content) { File.read(File.join(template_dir, "baymax_triage.yml")) }

    it "is valid YAML" do
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "triggers on repository_dispatch" do
      workflow = YAML.safe_load(content)
      # YAML parses bare `on` as boolean true
      expect(workflow.dig(true, "repository_dispatch", "types")).to eq(["baymax"])
    end
  end

  describe "baymax_verify.yml" do
    let(:content) { File.read(File.join(template_dir, "baymax_verify.yml")) }

    it "is valid YAML" do
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "triggers on pull_request events" do
      workflow = YAML.safe_load(content)
      # YAML parses bare `on` as boolean true
      expect(workflow.dig(true, "pull_request", "types")).to include("opened", "labeled")
    end
  end

  describe "generator file" do
    let(:generator_path) do
      File.expand_path(
        "../../../lib/generators/baymax/install/install_generator.rb",
        __dir__
      )
    end

    it "exists" do
      expect(File.exist?(generator_path)).to be(true)
    end

    it "defines the InstallGenerator class" do
      content = File.read(generator_path)
      expect(content).to include("class InstallGenerator < Rails::Generators::Base")
    end

    it "sets the correct namespace" do
      content = File.read(generator_path)
      expect(content).to include("namespace 'baymax:install'")
    end
  end
end

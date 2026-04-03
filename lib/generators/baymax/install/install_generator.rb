# frozen_string_literal: true

require 'rails/generators/base'

module Baymax
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      namespace 'baymax:install'

      desc 'Installs Baymax workflow, config, and prompt files'

      def copy_config
        say 'Adding Baymax settings...', :green
        copy_file 'baymax_settings.yml', 'config/baymax_settings.yml'
      end

      def copy_triage_workflow
        say 'Adding triage workflow...', :green
        copy_file 'baymax_triage.yml', '.github/workflows/baymax_triage.yml'
      end

      def copy_verify_workflow
        say 'Adding verify workflow...', :green
        copy_file 'baymax_verify.yml', '.github/workflows/baymax_verify.yml'
      end

      def copy_triage_prompt
        say 'Adding triage prompt...', :green
        copy_file 'baymax_triage.md', '.github/prompts/baymax_triage.md'
      end

      def copy_diagnosis_template
        say 'Adding diagnosis template...', :green
        copy_file 'baymax_diagnosis.md', '.github/prompts/baymax_diagnosis.md'
      end

      def copy_fix_instructions
        say 'Adding fix instructions template...', :green
        copy_file 'baymax_fix_instructions.md', '.github/prompts/baymax_fix_instructions.md'
      end

      def print_next_steps
        print_success_banner
        print_setup_instructions
      end

      private

      def print_success_banner
        say ''
        say '=' * 60, :green
        say '  Baymax installed successfully!', :green
        say '=' * 60, :green
      end

      def print_setup_instructions
        say ''
        say 'Next steps:', :yellow
        say ''
        print_infrastructure_steps
        print_configuration_steps
        say ''
      end

      def print_infrastructure_steps
        say '  1. Deploy telos-webhook-proxy to Cloudflare Workers'
        say '  2. Configure AppSignal/Rollbar webhooks to point at proxy URL'
        say '     Example: https://your-proxy.workers.dev/?repo=YourOrg/YourRepo'
        say '  3. Add GitHub Actions secrets:'
        print_secrets_list
      end

      def print_secrets_list
        say '     - ANTHROPIC_API_KEY (for LLM triage)'
        say '     - APPSIGNAL_API_KEY (if using AppSignal full details)'
        say '     - ROLLBAR_API_TOKEN (if using Rollbar full details)'
        say '     - AGENT_ASSIGN_TOKEN (optional, falls back to GITHUB_TOKEN)'
      end

      def print_configuration_steps
        say '  4. Review config/baymax_settings.yml and adjust thresholds'
        say '  5. Update .github/workflows/claude.yml permissions:'
        say '     contents: write, pull-requests: write'
        say '  6. Test locally:'
        say '     bundle exec baymax triage --fixture appsignal --dry-run --skip-llm'
      end
    end
  end
end

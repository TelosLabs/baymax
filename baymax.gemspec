# frozen_string_literal: true

require_relative 'lib/baymax/version'

Gem::Specification.new do |spec|
  spec.name = 'baymax'
  spec.version = Baymax::VERSION
  spec.authors = ['Telos Labs']
  spec.email = ['your@email.com']

  spec.summary = 'Production alert triage agent for Rails applications'
  spec.description = 'Receives production error alerts from AppSignal and Rollbar, ' \
                     'triages with LLM, creates GitHub issues, and dispatches AI agents for auto-fixes.'
  spec.homepage = 'https://github.com/TelosLabs/baymax'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['exe/**/*', 'lib/**/*', 'LICENSE.txt', 'README.md']
  spec.bindir = 'exe'
  spec.executables = ['baymax']
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 1.0'
  spec.add_dependency 'faraday-retry'
  spec.add_dependency 'railties', '>= 7.0'
  spec.add_dependency 'telos-agent-toolkit', '~> 0.1'
end

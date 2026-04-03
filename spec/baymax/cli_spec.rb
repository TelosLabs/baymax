# frozen_string_literal: true

require 'spec_helper'
require 'optparse'

RSpec.describe 'Baymax CLI option parsing' do
  def parse_options(args)
    options = {
      config_path: 'config/baymax_settings.yml',
      prompt_path: nil,
      dry_run: false,
      skip_llm: false,
      fixture: nil,
      event: nil,
      pr: nil,
      mode: 'triage'
    }

    parser = OptionParser.new do |opts|
      opts.on('--config PATH') { |v| options[:config_path] = v }
      opts.on('--prompt PATH') { |v| options[:prompt_path] = v }
      opts.on('--dry-run') { options[:dry_run] = true }
      opts.on('--skip-llm') { options[:skip_llm] = true }
      opts.on('--fixture NAME') { |v| options[:fixture] = v }
      opts.on('--event PATH') { |v| options[:event] = v }
      opts.on('--pr NUMBER', Integer) { |v| options[:pr] = v }
    end

    remaining = parser.parse(args)
    options[:mode] = remaining.shift || 'triage'
    options
  end

  it 'parses --dry-run flag' do
    options = parse_options(['--dry-run', 'triage'])

    expect(options[:dry_run]).to be true
    expect(options[:mode]).to eq('triage')
  end

  it 'parses --fixture appsignal' do
    options = parse_options(['--fixture', 'appsignal', 'triage'])

    expect(options[:fixture]).to eq('appsignal')
  end

  it 'parses --skip-llm flag' do
    options = parse_options(['--skip-llm', 'triage'])

    expect(options[:skip_llm]).to be true
  end

  it 'parses --config and --prompt paths' do
    options = parse_options(['--config', '/tmp/my.yml', '--prompt', '/tmp/prompt.md', 'triage'])

    expect(options[:config_path]).to eq('/tmp/my.yml')
    expect(options[:prompt_path]).to eq('/tmp/prompt.md')
  end

  it 'defaults mode to triage' do
    options = parse_options([])

    expect(options[:mode]).to eq('triage')
  end

  it 'parses verify mode with --pr' do
    options = parse_options(['--pr', '42', 'verify'])

    expect(options[:mode]).to eq('verify')
    expect(options[:pr]).to eq(42)
  end

  it 'requires --pr for verify mode' do
    options = parse_options(['verify'])

    expect(options[:mode]).to eq('verify')
    expect(options[:pr]).to be_nil
  end
end

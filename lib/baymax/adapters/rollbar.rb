# frozen_string_literal: true

module Baymax
  module Adapters
    class Rollbar < Base
      SEVERITY_MAP = {
        'info' => :info,
        'warning' => :warning,
        'warn' => :warning,
        'error' => :error,
        'critical' => :critical
      }.freeze

      MAX_MESSAGE_LENGTH = 500
      API_BASE = 'https://api.rollbar.com/api/1'

      def self.matches?(payload)
        payload['source'] == 'rollbar'
      end

      def normalize_webhook(payload)
        Telos::AgentToolkit::Alert.new(**extract_fields(payload))
      end

      private

      def extract_fields(payload)
        base_fields(payload).merge(
          error_message: truncate_message(payload['error_message']),
          severity: normalize_severity(payload['severity']),
          occurrence_count: payload['occurrence_count'].to_i,
          raw_payload: payload
        )
      end

      def base_fields(payload)
        { source: 'rollbar', error_class: payload['error_class'] || 'Unknown',
          revision: payload['revision'], app_name: payload['app_name'],
          incident_id: payload['incident_id']&.to_s }
      end

      # TODO: validate against real Rollbar API payloads
      def do_fetch_full_details(alert)
        token = ENV.fetch('ROLLBAR_API_TOKEN')
        conn = build_connection(API_BASE)
        response = conn.get("item/#{alert.incident_id}") do |req|
          req.headers['X-Rollbar-Access-Token'] = token
        end

        enrich_alert(alert, response.body)
      end

      def enrich_alert(alert, data)
        item = data['result'] || {}
        alert.with(
          error_message: truncate_message(item['title'] || alert.error_message),
          occurrence_count: item['total_occurrences']&.to_i || alert.occurrence_count
        )
      end

      def normalize_severity(value)
        SEVERITY_MAP.fetch(value.to_s.downcase, :info)
      end

      def truncate_message(message)
        return '' if message.nil?

        message.to_s[0, MAX_MESSAGE_LENGTH]
      end

      def build_connection(base_url)
        Faraday.new(url: base_url) do |f|
          f.response :raise_error
          f.response :json
        end
      end
    end
  end
end

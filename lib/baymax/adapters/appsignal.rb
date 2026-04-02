# frozen_string_literal: true

module Baymax
  module Adapters
    class Appsignal < Base
      SEVERITY_MAP = {
        'info' => :info,
        'warning' => :warning,
        'warn' => :warning,
        'error' => :error,
        'critical' => :critical
      }.freeze

      MAX_MESSAGE_LENGTH = 500
      API_BASE = 'https://appsignal.com/api'

      def self.matches?(payload)
        payload['source'] == 'appsignal'
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
        { source: 'appsignal', error_class: payload['error_class'] || 'Unknown',
          revision: payload['revision'], app_name: payload['app_name'],
          incident_id: payload['incident_id']&.to_s }
      end

      # TODO: validate against real AppSignal API payloads
      def do_fetch_full_details(alert)
        api_key = ENV.fetch('APPSIGNAL_API_KEY')
        conn = build_connection(API_BASE)
        response = conn.get("incidents/#{alert.incident_id}") do |req|
          req.params['token'] = api_key
        end

        enrich_alert(alert, response.body)
      end

      def enrich_alert(alert, data)
        alert.with(
          error_message: truncate_message(data['error_message'] || alert.error_message),
          occurrence_count: data['occurrence_count']&.to_i || alert.occurrence_count
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

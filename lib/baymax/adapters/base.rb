# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'logger'

module Baymax
  module Adapters
    class Base
      MAX_RETRIES = 3
      RETRY_DELAYS = [2, 4, 8].freeze

      class << self
        def registry
          @registry ||= []
        end

        def inherited(subclass)
          super
          Base.registry << subclass
        end

        def matches?(_payload)
          raise NotImplementedError, "#{name} must implement .matches?"
        end

        def detect(payload)
          adapter = registry.find { |a| a.matches?(payload) }
          raise ArgumentError, 'No adapter found for payload' unless adapter

          adapter.new
        end
      end

      def normalize_webhook(_payload)
        raise NotImplementedError, "#{self.class.name} must implement #normalize_webhook"
      end

      def fetch_full_details(alert)
        attempt_fetch(alert, retries: 0)
      end

      private

      def attempt_fetch(alert, retries:)
        do_fetch_full_details(alert)
      rescue StandardError => e
        retries += 1
        return retry_or_degrade(alert, e, retries) if retries <= MAX_RETRIES

        warn_and_degrade(alert, e)
      end

      def retry_or_degrade(alert, error, retries)
        sleep(RETRY_DELAYS[retries - 1] || RETRY_DELAYS.last)
        attempt_fetch(alert, retries: retries)
      rescue StandardError
        warn_and_degrade(alert, error)
      end

      def warn_and_degrade(alert, error)
        logger.warn("Persistent fetch failure for #{alert.incident_id}: #{error.message}. Returning degraded alert.")
        alert
      end

      def do_fetch_full_details(_alert)
        raise NotImplementedError, "#{self.class.name} must implement #do_fetch_full_details"
      end

      def logger
        @logger ||= Logger.new($stdout)
      end
    end
  end
end

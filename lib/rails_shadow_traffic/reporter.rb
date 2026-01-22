# frozen_string_literal: true

require 'active_support/notifications'

module RailsShadowTraffic
  # The Reporter class is responsible for publishing events related to the
  # shadow traffic comparison results using ActiveSupport::Notifications.
  # This allows other parts of the application to subscribe to these events
  # and react accordingly (e.g., logging, metrics, alerting).
  class Reporter
    # Publishes a notification based on the comparison results.
    #
    # @param payload [Hash] The original request payload.
    # @param original_response [Hash] The original response payload.
    # @param shadow_response [Net::HTTPResponse] The shadow response object.
    # @param mismatches [Array<Hash>] An array of differences found by the Differ.
    # @param config [RailsShadowTraffic::Config] The current configuration.
    def self.report(request_payload, original_response_payload, shadow_response, mismatches, config)
      # Ensure ActiveSupport::Notifications is available
      return unless defined?(ActiveSupport::Notifications)

      event_name = mismatches.empty? ? 'shadow_traffic.ok' : 'shadow_traffic.mismatch'
      
      # Build the notification payload
      notification_payload = {
        request: request_payload,
        original_response: original_response_payload,
        shadow_response: {
          status: shadow_response.code.to_i,
          headers: shadow_response.each_header.to_h,
          body: shadow_response.body # Note: this can be large, use with caution
        },
        mismatches: mismatches,
        config: config # Optionally pass the config, though it's a global singleton
      }

      ActiveSupport::Notifications.instrument(event_name, notification_payload)

      # Additionally, log to Rails.logger for immediate visibility
      if defined?(Rails.logger) && config.log_allowed?(:info)
        log_message = "[RailsShadowTraffic] Comparison Result: #{event_name.split('.').last.upcase}"
        log_message += " - Mismatches: #{mismatches.size}" unless mismatches.empty?
        log_message += " for request: #{request_payload[:method]} #{request_payload[:path]}"
        Rails.logger.info(log_message)
      end
    rescue => e
      if defined?(Rails.logger) && config.log_allowed?(:error)
        Rails.logger.error "[RailsShadowTraffic::Reporter] Failed to report comparison result: #{e.message}"
      end
    end

    # Reports an error during shadow request processing (e.g., client failure, job error).
    def self.report_error(request_payload, error, config)
      return unless defined?(ActiveSupport::Notifications)

      notification_payload = {
        request: request_payload,
        error: {
          class: error.class.to_s,
          message: error.message
        },
        config: config
      }

      ActiveSupport::Notifications.instrument('shadow_traffic.error', notification_payload)

      if defined?(Rails.logger) && config.log_allowed?(:error)
        Rails.logger.error "[RailsShadowTraffic] Shadow Request Error: #{error.class}: #{error.message} for request: #{request_payload[:method]} #{request_payload[:path]}"
      end
    rescue => e
      if defined?(Rails.logger) && config.log_allowed?(:error)
        Rails.logger.error "[RailsShadowTraffic::Reporter] Failed to report error: #{e.message}"
      end
    end
  end
end

# frozen_string_literal: true

require "active_job"
require "active_support/core_ext/hash/indifferent_access"
require_relative "client"
require_relative "differ"
require_relative "reporter"

module RailsShadowTraffic
  # This job is responsible for sending the shadowed request to the target
  # environment in the background, comparing its response to the original,
  # and reporting the results.
  class Job < ActiveJob::Base
    queue_as :default

    # Performs the shadow request, compares responses, and reports results.
    # @param payload [Hash] Contains the original request and response details.
    def perform(payload)
      request_payload = payload[:request].with_indifferent_access
      original_response_payload = payload[:original_response].with_indifferent_access
      config = RailsShadowTraffic.config

      if defined?(Rails.logger) && config.log_allowed?(:info)
        Rails.logger.info "[RailsShadowTraffic::Job] Sending shadow request for: #{request_payload[:method]} #{request_payload[:path]}"
      end

      shadow_response = nil
      begin
        client = Client.new(request_payload, config)
        shadow_response = client.send_request
      rescue => e
        Reporter.report_error(request_payload, e, config)
        return # Exit if the shadow request itself failed
      end

      # Compare responses if diffing is enabled and we got a shadow response
      if config.diff_enabled && shadow_response
        differ = Differ.new(original_response_payload, shadow_response, config)
        mismatches = differ.diff
        Reporter.report(request_payload, original_response_payload, shadow_response, mismatches, config)
      elsif defined?(Rails.logger) && config.log_allowed?(:info)
        Rails.logger.info "[RailsShadowTraffic::Job] Shadow request sent, diffing skipped or no shadow response received for: #{request_payload[:method]} #{request_payload[:path]}"
      end
    end
  end
end

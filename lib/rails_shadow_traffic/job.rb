# frozen_string_literal: true

require "active_job"

module RailsShadowTraffic
  # This job is responsible for sending the shadowed request to the target
  # environment in the background. It receives the necessary request details
  # and will use a client to perform the actual HTTP request.
  class Job < ActiveJob::Base
    queue_as :default

    # In a future step, this job will accept arguments containing the request
    # details (method, path, headers, body) and use an HTTP client to
    # send the request to the shadow target.
      def perform(payload)
        if defined?(Rails.logger)
          Rails.logger.info "[RailsShadowTraffic::Job] Sending shadow request for: #{payload[:method]} #{payload[:path]}"
        end
    
        # Instantiate the client and send the request.
        # The config is globally accessible via RailsShadowTraffic.config
        client = Client.new(payload.with_indifferent_access, RailsShadowTraffic.config)
        response = client.send_request
    
        if response && defined?(Rails.logger)
          Rails.logger.info "[RailsShadowTraffic::Job] Received shadow response: #{response.code} #{response.message}"
        end
    
        # In a future step, we would compare this response with the original
        # and report any differences.
      end  end
end

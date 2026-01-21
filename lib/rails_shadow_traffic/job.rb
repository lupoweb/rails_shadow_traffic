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
    def perform(*args)
      # For now, we just log that the job was executed.
      if defined?(Rails.logger)
        Rails.logger.info "[RailsShadowTraffic::Job] Executed with args: #{args.inspect}"
      end

      # TODO:
      # 1. Instantiate an HTTP client.
      # 2. Build the shadow request (method, URL, headers, body).
      # 3. Send the request.
      # 4. Receive the shadow response.
      # 5. Optionally perform a diff and report mismatches.
    end
  end
end

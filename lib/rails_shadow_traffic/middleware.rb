# frozen_string_literal: true

module RailsShadowTraffic
  # This middleware is the entry point for shadowing traffic. It intercepts
  # incoming requests, decides whether to shadow them based on the Sampler's
  # decision, and (in future steps) will dispatch the shadowing job.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Pass the request through to the application first, allowing it to complete
      # without being delayed by the shadow traffic logic.
      status, headers, response = @app.call(env)

      # After the main request is handled, decide if we should shadow this request.
      # This ensures we do not impact the response time for the user.
      if should_shadow?(env)
        # For now, we'll just log that we would have shadowed the request.
        # In a future step, this is where we will build and dispatch the
        # shadow payload to a background job.
        log_shadow_decision(env)
      end

      # Return the original application response.
      [status, headers, response]
    end

    private

    def should_shadow?(env)
      # Create a lightweight Rack::Request object to pass to the sampler.
      # We avoid creating this if the gem is disabled as a micro-optimization.
      return false unless RailsShadowTraffic.config.enabled

      request = Rack::Request.new(env)
      Sampler.sample?(request, RailsShadowTraffic.config)
    end

    def log_shadow_decision(env)
      return unless defined?(Rails.logger)

      method = env['REQUEST_METHOD']
      path = env['PATH_INFO']
      Rails.logger.info "[RailsShadowTraffic] Decision: YES. Would shadow request: #{method} #{path}"
    end
  end
end

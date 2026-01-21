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
        # The decision to shadow is made before the main app call,
        # but the job is dispatched after, to avoid delaying the response.
        should_shadow = should_shadow?(env)
        
        if should_shadow
          payload = build_payload_from_env(env)
        end
    
        status, headers, response = @app.call(env)
    
        if should_shadow && payload
          RailsShadowTraffic::Job.perform_later(payload)
        end
    
        [status, headers, response]
      end
    
      private
    
      def should_shadow?(env)
        return false unless RailsShadowTraffic.config.enabled
        # We create the request object once and pass it around if needed.
        request = Rack::Request.new(env)
        Sampler.sample?(request, RailsShadowTraffic.config)
      end
    
      # Extracts relevant details from the request environment into a serializable hash.
      def build_payload_from_env(env)
        request = Rack::Request.new(env)
        
        # Read and rewind the request body so the main application can still read it.
        body = request.body.read
        request.body.rewind
    
        {
          method: request.request_method,
          path: request.path,
          query_string: request.query_string,
          headers: extract_headers(env),
          body: body
        }
      end
    
      # Extracts HTTP headers from the Rack environment hash.
      def extract_headers(env)
        env.select { |k, _v| k.start_with?('HTTP_') }
           .transform_keys { |k| k.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-') }
      end
      end
end

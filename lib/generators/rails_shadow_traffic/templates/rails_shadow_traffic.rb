# frozen_string_literal: true

# config/initializers/rails_shadow_traffic.rb
#
# This file is the central configuration point for the RailsShadowTraffic gem.
# Uncomment and adjust the options below to suit your needs.

RailsShadowTraffic.configure do |config|
  # Enable or disable the shadow traffic gem completely.
  # It is recommended to only enable this in production-like environments.
  # Default: false
  # config.enabled = Rails.env.production?

  # The base URL of your shadow environment where requests will be mirrored.
  # This is required if `enabled` is true.
  # Example: "https://shadow-api.internal-staging.com"
  # config.target_url = ENV.fetch("SHADOW_TARGET_URL")

  # --- Sampling Configuration ---

  # The percentage of traffic to sample (a float between 0.0 and 1.0).
  # Default: 0.0 (no sampling)
  # config.sample_rate = 0.01 # Sample 1% of eligible requests

  # The sampling strategy to use.
  # :random: Purely random sampling. Good for getting a general sense of traffic.
  # :stable_hash: Attempts to provide stable sampling for the same identifier.
  #               This is useful for consistently shadowing a specific user, session, or tenant.
  # Default: :random
  # config.sampler = :stable_hash

  # An optional secret key for HMAC-based stable hashing.
  # If provided, `stable_hash` mode will use HMAC-SHA256, making sampling decisions
  # less predictable and more robust against client-controlled identifiers.
  # Default: nil
  # config.sampling_key = ENV.fetch("SHADOW_SAMPLING_KEY", nil)

  # A lambda to extract a stable identifier from a request (e.g., session ID, tenant ID).
  # This is used in `:stable_hash` sampling mode. If nil, `X-Request-Id` is used as a fallback.
  # Example: ->(req) { req.get_header("HTTP_X_SESSION_ID") }
  # Default: nil
  # config.identifier_extractor = ->(req) { req.get_header("HTTP_X_TENANT_ID") }

  # A lambda to add context to the identifier before hashing for stable sampling.
  # This allows the same identifier to be sampled differently based on context (e.g., path).
  # Example: ->(req, id) { "#{id}:#{req.path_info}" }
  # Default: nil
  # config.hash_scope = ->(req, id) { "#{id}:#{req.path_info}" }

  # An array of HTTP methods to consider for shadowing.
  # Default: ['GET'] (starting with only idempotent methods is safer)
  # config.only_methods = %w[GET POST PUT]

  # An array of paths or regular expressions to consider for shadowing.
  # An empty array means all paths are eligible.
  # Example: [%r{\A/api/v1/users}, "/legacy/data"]
  # Default: []
  # config.only_paths = [%r{\A/api/v2/}]

  # A lambda for dynamic sampling decisions. It receives the `Rack::Request` object.
  # This code runs for every request that passes the above checks, so it must be fast.
  # It must be a "pure predicate" (no IO, no locks, no external calls).
  # Default: ->(req) { true }
  # config.condition = ->(req) { req.get_header("HTTP_X_INTERNAL_USER") == "true" }

  # Timeout in seconds for the `condition` lambda. If the condition takes longer
  # than this, it will be aborted, and the request won't be shadowed.
  # Clamped to a maximum of 0.1s for safety.
  # Default: 0.01 (10ms)
  # config.condition_timeout = 0.05 # 50ms

  # Number of `condition` failures (timeouts or errors) before the circuit breaker
  # opens, temporarily disabling the condition to protect the application.
  # Default: 10
  # config.condition_failure_threshold = 5

  # Seconds to wait before the circuit breaker resets after opening.
  # Default: 60 (1 minute)
  # config.condition_circuit_cooldown = 300 # 5 minutes

  # --- Data Scrubbing Configuration ---

  # A list of header names to be removed from the request before sending it
  # to the shadow target. Matching is case-insensitive.
  # Default: ['Authorization', 'Cookie']
  # config.scrub_headers = ['Authorization', 'Cookie', 'X-Api-Key']

  # A list of JSON keys whose values will be masked in the request body.
  # This works on nested keys.
  # Default: ['password', 'token', 'credit_card', 'cvv', 'ssn']
  # config.scrub_json_fields = ['password', 'email', 'user.api_token']

  # The string used to replace sensitive data in JSON bodies.
  # Default: '[FILTERED]'
  # config.scrub_mask = '***'

  # --- Response Diffing Configuration ---

  # Enables or disables the comparison between original and shadow responses.
  # If false, the shadow request is sent, but no comparison is performed.
  # Default: true
  # config.diff_enabled = false

  # A list of JSON paths (using dot notation, e.g., 'meta.timestamp', 'data.id')
  # to ignore during response body comparison. This is useful for volatile data
  # that is expected to change between requests.
  # Default: []
  # config.diff_ignore_json_paths = ['meta.timestamp', 'request_id']

  # --- Operational Configuration ---

  # Maximum number of log messages per second, per log level, to prevent log storms.
  # Default: 5
  # config.log_rate_limit_per_second = 10
end

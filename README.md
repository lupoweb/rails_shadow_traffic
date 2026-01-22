# RailsShadowTraffic

[![Gem Version](https://badge.fury.io/rb/rails_shadow_traffic.svg)](https://badge.fury.io/rb/rails_shadow_traffic)
[![CI](https://github.com/lupoweb/rails_shadow_traffic/actions/workflows/ci.yml/badge.svg)](https://github.com/lupoweb/rails_shadow_traffic/actions/workflows/ci.yml)

RailsShadowTraffic is a powerful Ruby gem for mirroring a percentage of your production Rails application's traffic to a shadow environment. This allows you to test new features, refactors, or microservices with real-world production traffic, without impacting the end-user experience.

## Why use RailsShadowTraffic?

- **Risk-Free Testing**: Validate new code paths, microservices, or infrastructure changes against actual production traffic without exposing users to potential bugs.
- **Performance Validation**: Observe how your new services or code perform under real load conditions.
- **Behavioral Consistency**: Compare responses between your current and shadow environments to ensure the new implementation behaves as expected.
- **Early Detection**: Catch regressions or inconsistencies before deploying to actual users.

## Features

- **Configurable Sampling**: Decide which requests to shadow based on random percentage, stable hashing (per request ID/session ID), HTTP method, or URL path.
- **Dynamic Conditions**: Define custom Ruby procs to conditionally shadow requests based on any request attribute (headers, IP, user agent, etc.).
- **Sensitive Data Scrubbing**: Automatically remove or mask sensitive headers (e.g., `Authorization`, `Cookie`) and JSON body fields (e.g., `password`, `credit_card`) before sending to the shadow environment.
- **Asynchronous Dispatch**: Shadow requests are processed in background jobs (ActiveJob) to ensure zero impact on your primary application's response time.
- **Comprehensive Response Comparison**: Compare status codes, headers, and JSON bodies between original and shadow responses.
- **Ignorable JSON Paths**: Configure specific JSON paths (e.g., `$.meta.timestamp`) to ignore during response comparison, useful for volatile data.
- **Robust Error Handling**: Utilizes circuit breakers for dynamic conditions and rate-limits for logging to prevent system overload.
- **Extensible Reporting**: Publishes `ActiveSupport::Notifications` events for successful shadows, mismatches, and errors, allowing for custom logging, metrics, or alerting.

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem 'rails_shadow_traffic'
```

And then execute:

    $ bundle install

If you're using Rails, the gem will automatically load its `Railtie`.

## Configuration

RailsShadowTraffic is configured via a Rails initializer. You can generate a boilerplate initializer using:

    $ rails g rails_shadow_traffic:install

Or, manually create `config/initializers/rails_shadow_traffic.rb` with the following structure:

```ruby
RailsShadowTraffic.configure do |config|
  # Enable or disable the shadow traffic gem completely.
  # Default: false
  # config.enabled = Rails.env.production?

  # The base URL of your shadow environment where requests will be mirrored.
  # Required if `enabled` is true.
  # Example: "https://shadow-api.internal-staging.com"
  # config.target_url = ENV.fetch("SHADOW_TARGET_URL")

  # --- Sampling Configuration ---

  # The percentage of traffic to sample (0.0 to 1.0).
  # Default: 0.0 (no sampling)
  # config.sample_rate = 0.01 # Sample 1% of eligible requests

  # The sampling strategy to use.
  # :random: Purely random sampling.
  # :stable_hash: Attempts to provide stable sampling for the same identifier.
  #               Uses a hash of `X-Request-Id` (by default) or a custom identifier.
  # Default: :random
  # config.sampler = :stable_hash

  # An optional secret key for HMAC-based stable hashing.
  # If provided, `stable_hash` mode will use HMAC-SHA256, making sampling decisions
  # less predictable and more robust against client-controlled identifiers.
  # Default: nil
  # config.sampling_key = ENV.fetch("SHADOW_SAMPLING_KEY", nil)

  # A lambda to extract a stable identifier from a request (e.g., session ID, tenant ID).
  # This is used in `:stable_hash` sampling mode. If nil, `X-Request-Id` is used as default.
  # Example: ->(req) { req.get_header("HTTP_X_SESSION_ID") }
  # Default: nil (uses X-Request-Id)
  # config.identifier_extractor = ->(req) { req.get_header("HTTP_X_TENANT_ID") }

  # A lambda to add context to the identifier before hashing for stable sampling.
  # This allows the same identifier to be sampled differently based on context (e.g., path).
  # Example: ->(req, id) { "#{id}:#{req.path_info}" }
  # Default: nil (identifier is hashed directly)
  # config.hash_scope = ->(req, id) { "#{id}:#{req.path_info}" }

  # An array of HTTP methods to consider for shadowing.
  # Default: ['GET'] (only idempotent methods for safety)
  # config.only_methods = %w[GET POST PUT]

  # An array of paths or regular expressions to consider for shadowing.
  # Empty array means all paths are eligible.
  # Example: [%r{\A/api/v1/users}, "/legacy/data"]
  # Default: []
  # config.only_paths = []

  # A lambda for dynamic sampling decisions. It receives the `Rack::Request` object.
  # This must be a "pure predicate" (no IO, no locks, no external calls).
  # Default: ->(req) { true }
  # config.condition = ->(req) { req.get_header("HTTP_X_INTERNAL_USER") == "true" }

  # Timeout in seconds for the `condition` lambda. If the condition takes longer
  # than this, it will be aborted, the request won't be shadowed, and a warning logged.
  # Clamped to a maximum of 0.1s for safety.
  # Default: 0.01 (10ms)
  # config.condition_timeout = 0.05 # 50ms

  # Number of `condition` failures (timeouts or errors) before the circuit breaker
  # opens, temporarily disabling the condition to protect the application.
  # Default: 10
  # config.condition_failure_threshold = 5

  # Seconds to wait before the circuit breaker resets after opening, allowing
  # the `condition` to be re-evaluated.
  # Default: 60 (1 minute)
  # config.condition_circuit_cooldown = 300 # 5 minutes

  # --- Data Scrubbing Configuration ---

  # A list of header names to be removed from the request before sending it
  # to the shadow target. Case-insensitive matching.
  # Default: ['Authorization', 'Cookie']
  # config.scrub_headers = ['Authorization', 'Cookie', 'X-API-Key']

  # A list of JSON keys to be masked in the request body. Works on nested keys.
  # Default: ['password', 'token', 'credit_card', 'cvv', 'ssn']
  # config.scrub_json_fields = ['password', 'email']

  # The string used to replace sensitive data in JSON bodies.
  # Default: '[FILTERED]'
  # config.scrub_mask = '***'

  # --- Response Diffing Configuration ---

  # Enables or disables the comparison between original and shadow responses.
  # If false, only the shadow request is sent.
  # Default: true
  # config.diff_enabled = false

  # A list of JSON paths (using dot notation, e.g., 'meta.timestamp', 'data.id')
  # to ignore during response body comparison. Useful for volatile data.
  # Default: []
  # config.diff_ignore_json_paths = ['meta.timestamp', 'request_id']

  # --- Operational Configuration ---

  # Maximum number of log messages per second, per log level, to prevent log storms
  # when the gem encounters frequent issues (e.g., condition timeouts).
  # Default: 5
  # config.log_rate_limit_per_second = 10
end
```

## Usage

Once configured, RailsShadowTraffic will automatically intercept requests and dispatch shadow requests in the background.

### Subscribing to Notifications

RailsShadowTraffic publishes `ActiveSupport::Notifications` events that you can subscribe to in your application to monitor its behavior and collect metrics.

```ruby
# config/initializers/shadow_traffic_subscribers.rb
ActiveSupport::Notifications.subscribe('shadow_traffic.ok') do |name, start, finish, id, payload|
  # A shadow request was successfully sent and responses matched.
  Rails.logger.info "[ShadowTraffic] OK: #{payload[:request][:method]} #{payload[:request][:path]}"
  # Increment a metric counter, e.g., Datadog.increment('shadow_traffic.ok')
end

ActiveSupport::Notifications.subscribe('shadow_traffic.mismatch') do |name, start, finish, id, payload|
  # A shadow request was sent, but responses did not match.
  Rails.logger.warn "[ShadowTraffic] MISMATCH: #{payload[:request][:method]} #{payload[:request][:path]} - Mismatches: #{payload[:mismatches].size}"
  payload[:mismatches].each do |mismatch|
    Rails.logger.warn "  - Type: #{mismatch[:type]}, Original: #{mismatch[:original]}, Shadow: #{mismatch[:shadow]}"
  end
  # Send an alert, store mismatch details, etc.
end

ActiveSupport::Notifications.subscribe('shadow_traffic.error') do |name, start, finish, id, payload|
  # An error occurred during shadow request processing (e.g., client failed, condition timeout).
  Rails.logger.error "[ShadowTraffic] ERROR: #{payload[:error][:class]}: #{payload[:error][:message]} for #{payload[:request][:method]} #{payload[:request][:path]}"
  # Increment an error metric, alert a monitoring system.
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/lupoweb/rails_shadow_traffic](https://github.com/lupoweb/rails_shadow_traffic). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/lupoweb/rails_shadow_traffic/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RailsShadowTraffic project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/lupoweb/rails_shadow_traffic/blob/main/CODE_OF_CONDUCT.md).
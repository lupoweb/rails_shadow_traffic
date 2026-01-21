# frozen_string_literal: true

require "timeout"
require "digest/md5"
begin
  require "openssl"
rescue LoadError
  # OpenSSL might not be available in some minimal environments.
  # The HMAC feature will be disabled in this case.
end

module RailsShadowTraffic
  # Decides whether a given request should be sampled for shadowing based on a
  # rich set of rules defined in the configuration.
  # The checks are ordered from cheapest to most expensive to optimize performance.
  module Sampler
    # Performs the sampling decision.
    #
    # @param request [Rack::Request] The incoming request object.
    # @param config [RailsShadowTraffic::Config] The current configuration.
    # @return [Boolean] `true` if the request should be shadowed, `false` otherwise.
    def self.sample?(request, config)
      # --- Cheap Checks First ---
      return false unless config.enabled
      return false unless method_allowed?(request, config)
      return false unless path_allowed?(request, config)

      rate = config.sample_rate
      return false if rate <= 0.0

      # If rate is 100%, we still need to check the condition, but we can bypass
      # the rate-specific sampling logic.
      if rate >= 1.0
        return condition_met?(request, config)
      end

      # --- Expensive Checks Last ---
      return false unless rate_allowed?(request, config, rate)

      condition_met?(request, config)
    end

    private

    # Checks if the request's HTTP method is in the allow-list.
    def self.method_allowed?(request, config)
      # Assumes config.only_methods is frozen and upcased by Config#finalize!
      config.only_methods.empty? || config.only_methods.include?(request.request_method)
    end

    # Checks if the request's path matches any of the specified patterns.
    def self.path_allowed?(request, config)
      patterns = config.only_paths
      return true if patterns.empty?

      path = request.path_info
      patterns.any? do |p|
        p.is_a?(Regexp) ? p.match?(path) : path == p
      end
    end

    # Checks if the request passes the sampling rate decision (`:random` or `:stable_hash`).
    def self.rate_allowed?(request, config, rate)
      case config.sampler
      when :random
        Kernel.rand < rate
      when :stable_hash
        identifier = extract_identifier(request, config)
        return false unless identifier

        # Apply the hash_scope if defined
        scoped_identifier = config.hash_scope ? config.hash_scope.call(request, identifier) : identifier

        h32 = hash32(scoped_identifier.to_s, config)
        threshold = (rate * (2**32)).to_i
        h32 < threshold
      else
        Kernel.rand < rate # Fallback to random for unknown samplers
      end
    end

    # Extracts a stable identifier from the request using the configured extractor.
    def self.extract_identifier(request, config)
      if config.identifier_extractor
        v = config.identifier_extractor.call(request)
        return v.to_s unless v.nil? || v.to_s.empty?
      end
      # Default: try to get X-Request-Id if no extractor is provided
      rid = request.get_header("HTTP_X_REQUEST_ID")
      rid.to_s unless rid.nil? || rid.to_s.empty?
    rescue => e
      safe_log_error(config, "identifier_extractor failed: #{e.message}")
      nil
    end

    # Hashes the identifier to a 32-bit integer. Uses HMAC for security if a key is provided,
    # otherwise defaults to MD5 for speed and good distribution.
    def self.hash32(identifier, config)
      key = config.sampling_key
      if key && defined?(OpenSSL::HMAC)
        # Secure path: HMAC-SHA256, taking the first 4 bytes.
        digest = OpenSSL::HMAC.digest("SHA256", key, identifier)
        digest.unpack1("L>") # Unsigned 32-bit, big-endian
      else
        # Fast path: MD5, taking the first 4 bytes. Better distribution than CRC32.
        digest = Digest::MD5.digest(identifier)
        digest.unpack1("L>")
      end
    end

    # Checks if the dynamic `condition` lambda passes.
    # This is the most expensive check and is protected by a timeout and circuit breaker.
    def self.condition_met?(request, config)
      return true unless config.condition

      # Check the circuit breaker before attempting to run the condition
      return false if config.circuit_open?

      # The bang-bang (!!) ensures the result is always a boolean
      !!Timeout.timeout(config.condition_timeout) { config.condition.call(request) }
    rescue Timeout::Error
      config.record_condition_failure!
      safe_log_warn(config, "condition timed out after #{config.condition_timeout}s")
      false
    rescue => e
      config.record_condition_failure!
      safe_log_error(config, "condition failed: #{e.class}: #{e.message}")
      false
    end

    # Helper to log warnings with rate-limiting.
    def self.safe_log_warn(config, msg)
      return unless defined?(Rails) && Rails.respond_to?(:logger)
      return unless config.log_allowed?(:warn)
      Rails.logger.warn("RailsShadowTraffic: #{msg}")
    end

    # Helper to log errors with rate-limiting.
    def self.safe_log_error(config, msg)
      return unless defined?(Rails) && Rails.respond_to?(:logger)
      return unless config.log_allowed?(:error)
      Rails.logger.error("RailsShadowTraffic: #{msg}")
    end
  end
end

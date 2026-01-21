# frozen_string_literal: true

require "singleton"
require "monitor"
require "logger"

module RailsShadowTraffic
  # This class holds the configuration for the RailsShadowTraffic gem.
  # It's designed as a singleton to be accessible globally via RailsShadowTraffic.config
  #
  # It includes sophisticated features for production-grade operation:
  # - A thread-safe, in-memory circuit breaker for the sampling condition.
  # - A thread-safe, time-based rate limiter for logging to prevent log storms.
  # - Fail-fast validations and finalization to ensure a robust setup.
  class Config
    include Singleton
    include MonitorMixin

    # @!attribute [rw] enabled
    #   @return [Boolean] Enables or disables the gem entirely. Default: `false`.
    attr_accessor :enabled

    # @!attribute [rw] sample_rate
    #   @return [Float] The percentage of traffic to shadow (0.0 to 1.0). Default: `0.0`.
    attr_accessor :sample_rate

    # @!attribute [rw] sampler
    #   @return [Symbol] The sampling strategy. `:random` or `:stable_hash`. Default: `:random`.
    attr_accessor :sampler

    # @!attribute [rw] sampling_key
    #   @return [String, nil] An optional secret key for HMAC-based stable hashing, preventing sampling abuse. Default: `nil`.
    attr_accessor :sampling_key

    # @!attribute [rw] identifier_extractor
    #   @return [Proc, nil] A lambda to extract a stable identifier from a request (e.g., session ID, tenant ID).
    #     Example: `->(req) { req.get_header("HTTP_X_SESSION_ID") }`. Default: `nil`.
    attr_accessor :identifier_extractor

    # @!attribute [rw] hash_scope
    #   @return [Proc, nil] A lambda to generate a scope for hashing, allowing the same identifier to be sampled
    #     differently based on context (e.g., path). Example: `->(req, id) { "#{id}:#{req.path_info}" }`. Default: `nil`.
    attr_accessor :hash_scope

    # @!attribute [rw] only_methods
    #   @return [Array<String>] An array of HTTP methods to consider for shadowing. Default: `['GET']`.
    attr_accessor :only_methods

    # @!attribute [rw] only_paths
    #   @return [Array<String, Regexp>] An array of paths/patterns to consider for shadowing. Default: `[]`.
    attr_accessor :only_paths

    # @!attribute [rw] condition
    #   @return [Proc, nil] A lambda for dynamic sampling decisions. Must be a "pure predicate". Default: `->(req) { true }`.
    attr_accessor :condition

    # @!attribute [rw] condition_timeout
    #   @return [Float] Timeout in seconds for the `condition` lambda. Default: `0.01` (10ms).
    attr_accessor :condition_timeout

    # @!attribute [rw] condition_failure_threshold
    #   @return [Integer] Number of `condition` failures before opening the circuit breaker. Default: `10`.
    attr_accessor :condition_failure_threshold

    # @!attribute [rw] condition_circuit_cooldown
    #   @return [Integer] Seconds to wait before resetting the circuit after it opens. Default: `60`.
    attr_accessor :condition_circuit_cooldown

    # @!attribute [rw] log_rate_limit_per_second
    #   @return [Integer] Max number of log messages per second, per log level, to prevent log storms. Default: `5`.
    attr_accessor :log_rate_limit_per_second

    # --- Internal State ---
    attr_reader :condition_failure_count, :circuit_last_opened_at

    def initialize
      super
      set_defaults
      @finalized = false
    end

    # Sets the configuration values to their defaults.
    def set_defaults
      @enabled = false
      @sample_rate = 0.0
      @sampler = :random
      @sampling_key = nil
      @identifier_extractor = nil
      @hash_scope = nil
      @only_methods = ['GET']
      @only_paths = []
      @condition = ->(_req) { true }
      @condition_timeout = 0.01 # 10ms
      @condition_failure_threshold = 10
      @condition_circuit_cooldown = 60 # 1 minute

      @log_rate_limit_per_second = 5
      @log_timestamps = {} # { warn: [t1, t2], error: [t1] }

      @condition_failure_count = 0
      @circuit_last_opened_at = nil
    end

    # Validates the configuration, raising an error if any value is invalid.
    def validate!
      raise ArgumentError, "sample_rate must be between 0.0 and 1.0" unless (0.0..1.0).cover?(@sample_rate)
      raise ArgumentError, "sampler must be :random or :stable_hash" unless [:random, :stable_hash].include?(@sampler)
      raise ArgumentError, "only_methods must be an Array" unless @only_methods.is_a?(Array)
      raise ArgumentError, "only_paths must be an Array" unless @only_paths.is_a?(Array)
      raise ArgumentError, "condition must be a Proc" unless @condition.is_a?(Proc)
      raise ArgumentError, "condition_timeout must be a positive number" if @condition_timeout.to_f <= 0
      @condition_timeout = [@condition_timeout.to_f, 0.1].min # Clamp timeout to a max of 100ms
    end

    # Finalizes and freezes the configuration to prevent runtime changes.
    def finalize!
      validate!
      @only_methods.map!(&:to_s).map!(&:upcase).freeze
      @only_paths.freeze
      @finalized = true
      freeze
    end

    # --- Circuit Breaker Logic ---

    # Returns true if the circuit is open (i.e., the condition should be skipped).
    def circuit_open?
      synchronize do
        if @circuit_last_opened_at
          if Time.now.to_i > @circuit_last_opened_at + @condition_circuit_cooldown
            reset_circuit! # Cooldown has passed, reset the circuit
            false
          else
            true # Still in cooldown
          end
        else
          false # Circuit is closed
        end
      end
    end

    # Records a failure of the condition, potentially opening the circuit.
    def record_condition_failure!
      synchronize do
        @condition_failure_count += 1
        if @condition_failure_count >= @condition_failure_threshold
          @circuit_last_opened_at = Time.now.to_i
        end
      end
    end

    # --- Logging Logic ---

    # Returns true if a log message is allowed for the given level based on the rate limit.
    def log_allowed?(level)
      return true if @log_rate_limit_per_second <= 0

      synchronize do
        now = Time.now.to_i
        @log_timestamps[level] ||= []
        # Remove timestamps older than 1 second
        @log_timestamps[level].reject! { |ts| ts < now }

        if @log_timestamps[level].length < @log_rate_limit_per_second
          @log_timestamps[level] << now
          true
        else
          false
        end
      end
    end

    private

    # Resets the circuit breaker state.
    def reset_circuit!
      synchronize do
        @condition_failure_count = 0
        @circuit_last_opened_at = nil
      end
    end
  end
end

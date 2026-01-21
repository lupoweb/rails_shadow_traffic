# frozen_string_literal: true

require 'json'

module RailsShadowTraffic
  # This class is responsible for removing sensitive data from the request
  # payload before it's sent to the shadow environment.
  module Scrubber
    # Scrubs headers and body of a payload.
    #
    # @param payload [Hash] The request payload hash, which will be mutated.
    # @param config [RailsShadowTraffic::Config] The current configuration.
    # @return [void]
    def self.scrub!(payload, config)
      scrub_headers!(payload, config)
      scrub_body!(payload, config)
    end

    private

    # Removes sensitive headers from the payload.
    def self.scrub_headers!(payload, config)
      # Assumes scrub_headers in config are downcased and frozen.
      sensitive_headers = config.scrub_headers
      return if sensitive_headers.empty?

      payload[:headers].reject! do |key, _value|
        sensitive_headers.include?(key.to_s.downcase)
      end
    end

    # Masks sensitive fields in a JSON request body.
    def self.scrub_body!(payload, config)
      sensitive_fields = config.scrub_json_fields
      return if sensitive_fields.empty? || payload[:body].to_s.empty?

      # Check if the content type is JSON
      content_type = payload.dig(:headers, 'Content-Type').to_s
      return unless content_type.include?('application/json')

      begin
        json_body = JSON.parse(payload[:body])
        mask_fields!(json_body, sensitive_fields, config.scrub_mask)
        payload[:body] = JSON.generate(json_body)
      rescue JSON::ParserError
        # If the body is not valid JSON, we don't attempt to scrub it.
        # The request will be sent as-is.
      end
    end

    # Recursively traverses a hash or array and masks values of sensitive keys.
    def self.mask_fields!(data, sensitive_keys, mask)
      case data
      when Hash
        data.each do |key, value|
          if sensitive_keys.include?(key.to_s)
            data[key] = mask
          else
            mask_fields!(value, sensitive_keys, mask)
          end
        end
      when Array
        data.each { |item| mask_fields!(item, sensitive_keys, mask) }
      end
    end
  end
end

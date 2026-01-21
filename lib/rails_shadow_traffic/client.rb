# frozen_string_literal: true

require 'net/http'
require 'uri'

module RailsShadowTraffic
  # This class is responsible for sending the actual HTTP request to the shadow target.
  class Client
    # @param payload [Hash] The request payload captured by the middleware.
    #   It contains :method, :path, :query_string, :headers, and :body.
    # @param config [RailsShadowTraffic::Config] The current configuration.
    def initialize(payload, config)
      @payload = payload
      @config = config
    end

    # Builds and sends the HTTP request to the shadow target.
    def send_request
      base_url = @config.target_url
      return nil unless base_url

      uri = build_uri(base_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = build_http_request(uri)

      # Send the request and return the response.
      # Add timeouts for production-readiness
      http.open_timeout = 2 # seconds
      http.read_timeout = 5 # seconds
      http.request(request)
    rescue => e
      # Log any errors that occur during the request.
      safe_log_error("Request failed: #{e.message}")
      nil
    end

    private

    def build_uri(base_url)
      full_path = @payload[:query_string].to_s.empty? ? @payload[:path] : "#{@payload[:path]}?#{@payload[:query_string]}"
      URI.join(base_url, full_path)
    end

    def build_http_request(uri)
      method_class_name = @payload[:method].to_s.capitalize
      raise ArgumentError, "Unsupported HTTP method: #{method_class_name}" unless Net::HTTP.const_defined?(method_class_name)

      method_class = Net::HTTP.const_get(method_class_name)
      request = method_class.new(uri.request_uri)

      # Add headers from the original request.
      # In a real scenario, you would scrub sensitive headers here.
      @payload[:headers].each do |key, value|
        # Net::HTTP headers are case-insensitive but typically capitalized.
        # Some headers might not be valid, so we add them defensively.
        begin
          request[key] = value
        rescue ArgumentError => e
          safe_log_warn("Invalid header skipped: #{key} - #{e.message}")
        end
      end

      # Add the request body if present.
      request.body = @payload[:body] if @payload[:body] && !@payload[:body].empty?

      request
    end

    def safe_log_error(message)
      return unless defined?(Rails.logger) && RailsShadowTraffic.config.log_allowed?(:error)
      Rails.logger.error("[RailsShadowTraffic::Client] #{message}")
    end

    def safe_log_warn(message)
      return unless defined?(Rails.logger) && RailsShadowTraffic.config.log_allowed?(:warn)
      Rails.logger.warn("[RailsShadowTraffic::Client] #{message}")
    end
  end
end

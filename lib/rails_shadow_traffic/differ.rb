# frozen_string_literal: true

require 'json'
require 'active_support/core_ext/hash/indifferent_access'

module RailsShadowTraffic
  # Compares an original HTTP response with a shadow HTTP response to find differences.
  # It supports comparing status, headers, and JSON bodies, with options to ignore
  # specific JSON paths.
  class Differ
    # @param original_response [Hash] The original response payload (status, headers, body).
    # @param shadow_response [Net::HTTPResponse] The response object from Net::HTTP.
    # @param config [RailsShadowTraffic::Config] The current configuration.
    def initialize(original_response, shadow_response, config)
      @original = original_response.with_indifferent_access
      @shadow = shadow_response
      @config = config
      @mismatches = []
    end

    # Performs the comparison and returns an array of found differences.
    # Each difference is a hash describing the mismatch.
    # @return [Array<Hash>] An array of mismatch descriptions. Empty if no differences.
    def diff
      return [] unless @config.diff_enabled

      compare_status
      compare_headers
      compare_body

      @mismatches
    end

    private

    # Compares the HTTP status codes.
    def compare_status
      original_status = @original[:status].to_i
      shadow_status = @shadow.code.to_i
      return if original_status == shadow_status

      @mismatches << {
        type: :status,
        original: original_status,
        shadow: shadow_status
      }
    end

    # Compares HTTP headers.
    def compare_headers
      # Normalize headers for comparison (e.g., case-insensitivity)
      original_headers = normalize_headers(@original[:headers])
      shadow_headers = normalize_headers(@shadow.each_header.to_h)

      # Check for differences in keys and values
      (original_headers.keys | shadow_headers.keys).each do |key|
        original_value = original_headers[key]
        shadow_value = shadow_headers[key]

        next if original_value == shadow_value

        @mismatches << {
          type: :header,
          key: key,
          original: original_value,
          shadow: shadow_value
        }
      end
    end

    # Normalizes header keys to be consistent (e.g., lowercase for comparison).
    def normalize_headers(headers)
      headers.transform_keys(&:downcase)
    end

    # Compares response bodies. Supports JSON comparison with ignored paths.
    def compare_body
      original_body = @original[:body].to_s
      shadow_body = @shadow.body.to_s

      return if original_body == shadow_body

      original_content_type = @original[:headers].fetch('Content-Type', '').to_s
      shadow_content_type = @shadow.content_type.to_s

      # Only attempt JSON parsing if both are JSON
      if original_content_type.include?('application/json') && shadow_content_type.include?('application/json')
        compare_json_bodies(original_body, shadow_body)
      else
        @mismatches << {
          type: :body,
          format: :text,
          original: original_body,
          shadow: shadow_body
        }
      end
    end

    # Compares two JSON bodies after parsing and normalizing them.
    def compare_json_bodies(original_json_str, shadow_json_str)
      original_parsed = parse_and_normalize_json(original_json_str)
      shadow_parsed = parse_and_normalize_json(shadow_json_str)

      return if original_parsed == shadow_parsed

      @mismatches << {
        type: :body,
        format: :json,
        original: original_parsed,
        shadow: shadow_parsed
      }
    rescue JSON::ParserError => e
      @mismatches << {
        type: :body,
        format: :json_parse_error,
        error: e.message,
        original_raw: original_json_str,
        shadow_raw: shadow_json_str
      }
    end

    # Parses a JSON string and applies normalization (e.g., removing ignored paths).
    def parse_and_normalize_json(json_str)
      parsed_json = JSON.parse(json_str)

      # Remove ignored paths if configured
      if @config.diff_ignore_json_paths.any?
        remove_ignored_paths(parsed_json, @config.diff_ignore_json_paths)
      end

      parsed_json
    end

    # Recursively removes values at specified JSON paths.
    # Paths are simple dot-notation (e.g., 'user.address.street', 'items.0.id').
    def remove_ignored_paths(data, paths_to_ignore)
      return data unless data.is_a?(Hash) || data.is_a?(Array)

      paths_to_ignore.each do |path|
        segments = path.split('.')
        current_data = data
        parent_data = nil
        last_segment = nil

        segments.each_with_index do |segment, i|
          is_last_segment = (i == segments.length - 1)

          if current_data.is_a?(Hash)
            if is_last_segment
              current_data.delete(segment)
              break
            end
            parent_data = current_data
            current_data = current_data[segment]
            last_segment = segment
          elsif current_data.is_a?(Array) && segment =~ /^\d+$/
            index = segment.to_i
            if is_last_segment
              current_data.delete_at(index) if current_data[index]
              break
            end
            parent_data = current_data
            current_data = current_data[index]
            last_segment = index
          else
            # Path segment does not match data structure (e.g., trying to access hash key on array)
            break
          end
        end
      end
      data
    end
  end
end

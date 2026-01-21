# frozen_string_literal: true

require_relative "rails_shadow_traffic/version"
require_relative "rails_shadow_traffic/config"

module RailsShadowTraffic
  class Error < StandardError; end

  # Provides a global access point to the singleton Config instance.
  def self.config
    Config.instance
  end

  # Yields the singleton Config instance to a block for configuration.
  #
  # @example
  #   RailsShadowTraffic.configure do |config|
  #     config.enabled = true
  #     config.sample_rate = 0.05
  #   end
  def self.configure
    yield(config)
  end
end
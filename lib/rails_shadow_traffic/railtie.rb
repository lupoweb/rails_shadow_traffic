# frozen_string_literal: true

require "rails/railtie"

module RailsShadowTraffic
  # The Railtie is responsible for integrating the gem with a Rails application.
  # It handles the initialization process, including inserting the middleware
  # and finalizing the configuration.
  class Railtie < Rails::Railtie
      # The main initializer for the gem.
      # It inserts the Middleware into the application's middleware stack.
      initializer "rails_shadow_traffic.configure_rails_initialization" do |app|
        app.middleware.use RailsShadowTraffic::Middleware
      end
    
      # Using a `config.after_initialize` block ensures that the application's
      # own initializers (which is where the user will call `RailsShadowTraffic.configure`)
      # have already run.    config.after_initialize do
      # Finalize the configuration to make it immutable and apply validations.
      # This is a critical step for thread-safety and predictability.
      RailsShadowTraffic.config.finalize!

      # In a future step, we will log the effective configuration if a logger is present.
      # For example:
      # if defined?(Rails.logger)
      #   Rails.logger.info "RailsShadowTraffic enabled with sample rate: #{RailsShadowTraffic.config.sample_rate}"
      # end
    end
  end
end

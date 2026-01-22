# frozen_string_literal: true

require 'rails/generators'

module RailsShadowTraffic
  module Generators
    # This generator creates the initializer file for RailsShadowTraffic,
    # providing a boilerplate with all available configuration options commented out.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def copy_initializer_file
        template "rails_shadow_traffic.rb", "config/initializers/rails_shadow_traffic.rb"
      end
    end
  end
end

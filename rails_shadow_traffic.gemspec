# frozen_string_literal: true

require_relative "lib/rails_shadow_traffic/version"

Gem::Specification.new do |spec|
  spec.name = "rails_shadow_traffic"
  spec.version = RailsShadowTraffic::VERSION
  spec.authors = ["Francesco Lupano"]
  spec.email = ["lupano.web90@gmail.com"]

  spec.summary = "A Rails engine for shadowing production traffic."
  spec.description = "Provides middleware to mirror a configurable percentage of production traffic to a shadow environment for testing and validation, without impacting the primary user request."
  spec.homepage = "https://github.com/your-username/rails_shadow_traffic"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/your-username/rails_shadow_traffic"
  spec.metadata["changelog_uri"] = "https://github.com/your-username/rails_shadow_traffic/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "rack", ">= 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end

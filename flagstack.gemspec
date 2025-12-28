require_relative "lib/flagstack/version"

Gem::Specification.new do |spec|
  spec.name = "flagstack"
  spec.version = Flagstack::VERSION
  spec.authors = ["Flagstack"]
  spec.email = ["hello@flagstack.io"]

  spec.summary = "Feature flag client for Flagstack"
  spec.description = "Ruby client for Flagstack feature flag management. Syncs flags to local Flipper adapter for fast reads and offline resilience."
  spec.homepage = "https://flagstack.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/flagstack-dev/flagstack-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/flagstack-dev/flagstack-ruby/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "flipper", "~> 1.0"
  spec.add_dependency "logger", "~> 1.4"
end

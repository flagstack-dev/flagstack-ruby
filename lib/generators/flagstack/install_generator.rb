require "rails/generators"

module Flagstack
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a Flagstack initializer"

      def create_initializer
        template "flagstack.rb.tt", "config/initializers/flagstack.rb"
      end

      def show_instructions
        say ""
        say "Flagstack installed!", :green
        say ""
        say "Next steps:"
        say "  1. Get your API token from https://flagstack.io"
        say "  2. Add to your environment: FLAGSTACK_TOKEN=fs_dev_xxxxx"
        say "  3. Check flags: Flipper.enabled?(:my_feature)"
        say "  4. With users: Flipper.enabled?(:my_feature, current_user)"
        say ""
      end
    end
  end
end

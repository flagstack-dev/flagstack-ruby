module Flagstack
  class Railtie < Rails::Railtie
    initializer "flagstack.configure", after: :load_config_initializers do
      # Auto-configure when FLAGSTACK_TOKEN is present
      Flagstack.set_default
    end

    initializer "flagstack.configure_flipper", after: "flagstack.configure" do
      # If Flagstack is configured, set it as the default Flipper
      next unless Flagstack.configuration && Flagstack.flipper

      if defined?(Flipper)
        # Set Flagstack's Flipper instance as the default
        Flipper.instance = Flagstack.flipper
        Flagstack.configuration.log("Set Flagstack as default Flipper instance", level: :info)
      end
    end

    # Graceful shutdown when Rails exits
    config.after_initialize do
      at_exit do
        Flagstack.shutdown if Flagstack.configuration
      end
    end
  end
end

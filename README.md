# Flagstack Ruby Client

Ruby client for [Flagstack](https://flagstack.io) feature flag management. Drop-in replacement for Flipper Cloud.

## Installation

Add to your Gemfile:

```ruby
gem "flagstack"
gem "flipper"
gem "flipper-active_record"  # Recommended: for persistent local storage
```

Then run the generator:

```bash
rails generate flagstack:install
```

## Quick Start

Set your API token:

```bash
export FLAGSTACK_TOKEN=fs_live_your_token_here
```

That's it! Flagstack auto-configures when `FLAGSTACK_TOKEN` is present. Your existing Flipper code works unchanged:

```ruby
Flipper.enabled?(:new_checkout)
Flipper.enabled?(:beta_feature, current_user)
```

## How It Works

Flagstack mirrors Flipper Cloud's architecture:

```
                    +-----------------+
                    |    Flagstack    |
                    |  (cloud server) |
                    +--------+--------+
                             |
                             | sync (every 10-30s)
                             v
                    +--------+--------+
                    | Local Adapter   |
                    | (ActiveRecord   |
                    |  or Memory)     |
                    +--------+--------+
                             |
                             | all reads
                             v
                    +--------+--------+
                    |  Your App       |
                    | Flipper.enabled?|
                    +-----------------+
```

1. **Flagstack is the source of truth** - Manage flags in the Flagstack UI
2. **Data syncs to your local adapter** - Background poller keeps local data fresh
3. **All reads are local** - Zero network latency for `enabled?` checks
4. **Works offline** - If Flagstack is down, reads continue from local adapter

## Configuration

### Basic Configuration

```ruby
# config/initializers/flagstack.rb
Flagstack.configure do |config|
  config.token = ENV["FLAGSTACK_TOKEN"]
  config.sync_interval = 10  # seconds (minimum 10)
end
```

### Full Options

```ruby
Flagstack.configure do |config|
  # Required
  config.token = ENV["FLAGSTACK_TOKEN"]

  # Server (default: https://flagstack.io)
  config.url = ENV["FLAGSTACK_URL"]

  # Sync interval in seconds (default: 10, minimum: 10)
  config.sync_interval = 30

  # Sync method: :poll (background thread) or :manual
  config.sync_method = :poll

  # Telemetry (usage metrics)
  config.telemetry_enabled = true  # default: true
  config.telemetry_interval = 60   # seconds between submissions

  # HTTP timeouts in seconds
  config.read_timeout = 5
  config.open_timeout = 2
  config.write_timeout = 5

  # Local adapter (auto-detected if flipper-active_record is present)
  # Falls back to Memory adapter if not specified
  config.local_adapter = Flipper::Adapters::ActiveRecord.new

  # Logging
  config.logger = Rails.logger

  # Debug HTTP requests
  config.debug_output = $stderr

  # Instrumentation (for monitoring)
  config.instrumenter = ActiveSupport::Notifications
end
```

## Telemetry

Flagstack collects anonymous usage metrics to help you understand feature flag usage patterns. This data powers the Analytics dashboard in Flagstack.

### What's Collected

- Feature key (which flag was checked)
- Result (enabled/disabled)
- Timestamp (rounded to the minute)
- Count (aggregated locally before submission)

### Disabling Telemetry

```ruby
Flagstack.configure do |config|
  config.token = ENV["FLAGSTACK_TOKEN"]
  config.telemetry_enabled = false
end
```

## Usage

### With Rails (Recommended)

When `FLAGSTACK_TOKEN` is set, Flagstack automatically configures itself. You can use either the Flagstack API or Flipper directly:

```ruby
# Native Flagstack API (recommended for new projects)
Flagstack.enabled?(:new_checkout)
Flagstack.enabled?(:beta_feature, current_user)

# Flipper-compatible - existing code works unchanged
Flipper.enabled?(:new_checkout)
Flipper.enabled?(:beta_feature, current_user)

# Feature objects work too
Flagstack[:new_checkout].enabled?
Flipper[:new_checkout].enabled?
```

### Manual Configuration

```ruby
# config/initializers/flagstack.rb
flipper = Flagstack.configure do |config|
  config.token = ENV["FLAGSTACK_TOKEN"]
end

# Use the returned Flipper instance directly
flipper.enabled?(:new_checkout)

# Or access it later
Flagstack.flipper.enabled?(:new_checkout)
```

### Without Global State

For multi-tenant apps or testing:

```ruby
# Create separate instances (doesn't affect Flagstack.configuration)
flipper = Flagstack.new(token: "fs_live_xxx")
flipper.enabled?(:feature)
flipper.enabled?(:feature, current_user)
```

## Actor Setup

For percentage rollouts and actor targeting, your user model needs a `flipper_id`:

```ruby
class User < ApplicationRecord
  # Flipper expects this method for actor-based features
  def flipper_id
    "User_#{id}"
  end
end

# Then use it
Flipper.enabled?(:beta_feature, current_user)
```

## Local Features

You can still create local-only features that aren't synced from Flagstack:

```ruby
# Enable a local feature
Flipper.enable(:local_only_feature)

# It works alongside Flagstack features
Flipper.enabled?(:local_only_feature)  # true
Flipper.enabled?(:flagstack_feature)    # from Flagstack
```

Note: Flagstack sync only affects features that exist in Flagstack. Your local features are preserved.

## Token Types

| Prefix | Environment | Use |
|--------|-------------|-----|
| `fs_live_` | Production | Live traffic |
| `fs_test_` | Staging | Pre-production testing |
| `fs_dev_` | Development | Shared development |
| `fs_personal_` | Personal | Your local machine |

## API Reference

### Configuration

#### `Flagstack.configure { |config| }`

Configure and return a Flipper instance. Sets `Flagstack.configuration` and `Flagstack.flipper`.

#### `Flagstack.new(options)`

Create a standalone Flipper instance without affecting global state.

#### `Flagstack.flipper`

Returns the configured Flipper instance (after `configure`).

### Feature Flag Checks

#### `Flagstack.enabled?(feature, actor = nil)`

Check if a feature is enabled, optionally for a specific actor.

```ruby
Flagstack.enabled?(:new_checkout)
Flagstack.enabled?(:beta_feature, current_user)
```

#### `Flagstack.disabled?(feature, actor = nil)`

Check if a feature is disabled.

```ruby
Flagstack.disabled?(:maintenance_mode)
```

#### `Flagstack[feature]`

Access a feature object for method chaining.

```ruby
Flagstack[:new_checkout].enabled?
Flagstack[:new_checkout].enabled?(current_user)
```

### Feature Flag Management

#### `Flagstack.enable(feature)` / `Flagstack.disable(feature)`

Enable or disable a feature globally.

```ruby
Flagstack.enable(:new_feature)
Flagstack.disable(:old_feature)
```

#### `Flagstack.enable_actor(feature, actor)` / `Flagstack.disable_actor(feature, actor)`

Enable or disable a feature for a specific actor.

```ruby
Flagstack.enable_actor(:beta_feature, current_user)
```

#### `Flagstack.enable_group(feature, group)` / `Flagstack.disable_group(feature, group)`

Enable or disable a feature for a registered group.

```ruby
Flagstack.register(:admins) { |actor| actor.admin? }
Flagstack.enable_group(:admin_tools, :admins)
```

#### `Flagstack.enable_percentage_of_actors(feature, percentage)`

Enable a feature for a percentage of actors (deterministic based on actor ID).

```ruby
Flagstack.enable_percentage_of_actors(:new_feature, 25)  # 25% of users
```

#### `Flagstack.features`

List all features.

```ruby
Flagstack.features.each { |f| puts f.key }
```

### Utilities

#### `Flagstack.sync`

Force a sync from Flagstack to the local adapter.

#### `Flagstack.health_check`

Check connectivity to Flagstack server. Returns `{ ok: true/false, message: "..." }`.

```ruby
result = Flagstack.health_check
if result[:ok]
  puts "Connected: #{result[:message]}"
else
  puts "Error: #{result[:message]}"
end
```

#### `Flagstack.shutdown`

Gracefully stop the poller and flush any pending telemetry. Called automatically on Rails shutdown.

#### `Flagstack.reset!`

Reset everything (clears configuration, stops poller). Useful for testing.

## Testing

In your test setup:

```ruby
RSpec.configure do |config|
  config.before(:each) do
    Flagstack.reset!
  end
end
```

For isolated tests, use `Flagstack.new` with a test token or stub the HTTP calls:

```ruby
# With WebMock
stub_request(:get, "https://flagstack.io/api/v1/sync")
  .to_return(
    status: 200,
    body: { features: [{ key: "test_feature", enabled: true, gates: {} }] }.to_json
  )

stub_request(:post, "https://flagstack.io/api/v1/telemetry")
  .to_return(status: 202)

flipper = Flagstack.new(token: "fs_test_xxx")
expect(flipper.enabled?(:test_feature)).to be true
```

## Migrating from Flipper Cloud

Flagstack is designed as a drop-in replacement:

1. Replace `FLIPPER_CLOUD_TOKEN` with `FLAGSTACK_TOKEN`
2. Replace `gem "flipper-cloud"` with `gem "flagstack"`
3. Your `Flipper.enabled?` calls work unchanged

## License

MIT

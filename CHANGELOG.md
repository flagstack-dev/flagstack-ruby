# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-12-27

### Added

- Initial release
- Native Flagstack API: `Flagstack.enabled?`, `Flagstack.disabled?`, `Flagstack.enable`, `Flagstack.disable`
- Actor targeting: `Flagstack.enable_actor`, `Flagstack.disable_actor`
- Group targeting: `Flagstack.enable_group`, `Flagstack.disable_group`, `Flagstack.register`
- Percentage rollouts: `Flagstack.enable_percentage_of_actors`, `Flagstack.enable_percentage_of_time`
- Feature access: `Flagstack[:feature]`, `Flagstack.features`
- Health check method (`Flagstack.health_check`) to verify connectivity to Flagstack server
- Graceful shutdown hooks for Rails applications via `at_exit`
- Feature flag synchronization from Flagstack to local Flipper adapter
- Background polling for automatic sync (configurable interval)
- Telemetry support for feature flag evaluation metrics
- Support for all Flipper gate types:
  - Boolean (enabled/disabled)
  - Actors (specific users/entities)
  - Groups (named groups)
  - Percentage of actors
  - Percentage of time
- Rails integration via Railtie
- Auto-configuration when `FLAGSTACK_TOKEN` environment variable is set
- Install generator (`rails generate flagstack:install`)
- Fork detection for multi-process servers (Puma, Unicorn)
- ETag-based caching for efficient sync
- Offline resilience (reads continue from local adapter if Flagstack is unavailable)

### Configuration Options

- `token` - API token (required)
- `url` - Flagstack server URL (default: https://flagstack.io)
- `sync_interval` - Polling interval in seconds (default: 10)
- `sync_method` - `:poll` or `:manual` (default: :poll)
- `telemetry_enabled` - Enable/disable telemetry (default: true)
- `telemetry_interval` - Telemetry submission interval (default: 60)
- `local_adapter` - Custom Flipper adapter (auto-detected)
- `logger` - Custom logger (default: Rails.logger or stdlib Logger)
- `read_timeout`, `open_timeout`, `write_timeout` - HTTP timeouts

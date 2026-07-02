# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sidekiq-unique-jobs is a Sidekiq middleware gem that prevents duplicate jobs from being enqueued or executed. It provides sophisticated locking mechanisms using Redis to ensure job uniqueness based on configurable parameters.

## Development Commands

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/spec.rb

# Run specific test by line number
bundle exec rspec spec/path/to/spec.rb:42

# Run tests with specific appraisals (different Sidekiq versions)
bundle exec appraisal rspec
bundle exec appraisal sidekiq-6.0 rspec
```

### Code Quality
```bash
# Run rubocop linter
bundle exec rake rubocop

# Run reek (code smell detector)
bundle exec rake reek

# Run all style checks
bundle exec rake style

# Generate documentation
bundle exec rake yard
```

### Build and Release
```bash
# Run all checks (style, tests, documentation)
bundle exec rake

# Release a new gem version (only for maintainers)
bundle exec rake release
```

## Architecture

### Lock Types

The gem implements multiple lock strategies that control when and how uniqueness is enforced:

1. **Client-side locks** (prevent duplicate enqueuing):
   - `until_executing` - Lock from push until job starts executing
   - `until_executed` - Lock from push until job completes execution
   - `until_expired` - Lock from push until configured TTL expires
   - `until_and_while_executing` - Combination lock (both phases)

2. **Server-side locks** (prevent duplicate execution):
   - `while_executing` - Lock only during job execution
   - `while_executing_reject` - Same as above but rejects conflicts

Lock implementations inherit from `SidekiqUniqueJobs::Lock::BaseLock` (lib/sidekiq_unique_jobs/lock/base_lock.rb) and implement two key methods:
- `lock` - Attempt to acquire the lock
- `execute` - Execute the job with appropriate lock behavior

### Core Components

**Middleware Stack:**
- `SidekiqUniqueJobs::Middleware::Client` - Intercepts job enqueuing
- `SidekiqUniqueJobs::Middleware::Server` - Intercepts job execution
- These must be manually configured in Sidekiq initializer (not auto-loaded)

**Lock Management:**
- `Locksmith` (lib/sidekiq_unique_jobs/locksmith.rb) - Central lock manager that interfaces with Redis
- `LockDigest` - Generates unique digest from job parameters (queue, class, args)
- `LockConfig` - Extracts and normalizes lock configuration from job options
- `Key` - Manages Redis key naming with configurable prefixes

**Conflict Resolution:**
- Strategies in `lib/sidekiq_unique_jobs/on_conflict/` handle lock conflicts:
  - `log` - Log the conflict
  - `raise` - Raise exception (for retry)
  - `reject` - Send to dead queue
  - `replace` - Delete existing job and retry
  - `reschedule` - Delay and retry
- Inherit from `SidekiqUniqueJobs::OnConflict::Strategy`

**Lua Scripts:**
- All Redis operations use Lua scripts in `lib/sidekiq_unique_jobs/lua/`
- This ensures atomic operations and consistency
- Scripts are loaded and executed via `Script::Caller` mixin
- Template system with shared functions in `lua/shared/`

**Orphan Cleanup:**
- `SidekiqUniqueJobs::Orphans::Manager` - Coordinates reaper lifecycle
- `SidekiqUniqueJobs::Orphans::RubyReaper` - Ruby-based cleanup (default)
- `SidekiqUniqueJobs::Orphans::LuaReaper` - Lua-based cleanup (faster but locks Redis)
- Reapers run periodically to clean up stale locks from crashed processes

### Configuration System

Global configuration via `SidekiqUniqueJobs.configure` block:
- Uses `Concurrent::MutableStruct` for thread-safe config
- Defined in `lib/sidekiq_unique_jobs/config.rb`
- Supports custom locks and strategies via `add_lock` and `add_strategy`

Per-worker configuration via `sidekiq_options`:
- `lock` - Lock type (required)
- `on_conflict` - Conflict strategy (can differ for client/server)
- `lock_timeout` - How long to wait for lock acquisition
- `lock_ttl` - Lock expiration time
- `lock_args_method` - Custom method/proc to filter uniqueness args
- `unique_across_queues` - Ignore queue in digest calculation
- `unique_across_workers` - Ignore worker class in digest calculation

### Redis Integration

The gem uses `redis-client` (not `redis` gem) via Sidekiq's connection pool. Wrapper classes in `lib/sidekiq_unique_jobs/redis/` provide object-oriented interfaces:
- `Redis::String` - String operations
- `Redis::Hash` - Hash operations
- `Redis::Set` - Set operations
- `Redis::SortedSet` - Sorted set operations
- `Redis::List` - List operations

All inherit from `Redis::Entity` base class.

### Reflection System

The gem provides hooks for observability (metrics, logging) via `SidekiqUniqueJobs.reflect`:
- `locked` - Lock acquired successfully
- `lock_failed` - Could not acquire lock
- `unlocked` - Lock released
- `unlock_failed` - Lock release failed
- `timeout` - Lock acquisition timed out
- `execution_failed` - Job execution raised error
- Other reflection points defined in `lib/sidekiq_unique_jobs/reflections.rb`

## Testing Guidelines

- Integration tests in `spec/sidekiq_unique_jobs/lock/*_spec.rb` cover each lock type end-to-end
- Lua script tests in `spec/sidekiq_unique_jobs/lua/*_spec.rb` verify Redis operations
- Use `SidekiqUniqueJobs.use_config` to temporarily override config in tests
- Disable uniqueness in tests with `SidekiqUniqueJobs.config.enabled = false`
- Use `Sidekiq::Testing.disable!` and clear Redis when testing actual uniqueness behavior

## Important Patterns

**Lock Arguments Filtering:**
Workers can define `self.lock_args(args)` class method or use `lock_args_method` proc to customize which arguments determine uniqueness. This is critical for jobs with transient parameters.

**Digest Algorithm:**
Two digest algorithms available:
- `:legacy` (default) - Uses MD5, may have issues with FIPS-enabled Redis
- `:modern` - FIPS-compatible alternative

**Middleware Ordering:**
When using with other Sidekiq middleware gems (apartment-sidekiq, sidekiq-global_id, sidekiq-status), order matters. Generally, this gem's middleware should run last on the client side and last on the server side (see README for specific gem combinations).

**After Unlock Callbacks:**
Workers can define `after_unlock` instance or class method for cleanup after lock release. Note: `until_expired` locks never call this callback.

## File Structure

- `lib/sidekiq_unique_jobs.rb` - Main entry point, requires all dependencies
- `lib/sidekiq_unique_jobs/lock/` - Lock type implementations
- `lib/sidekiq_unique_jobs/on_conflict/` - Conflict resolution strategies
- `lib/sidekiq_unique_jobs/lua/` - Lua scripts for atomic Redis operations
- `lib/sidekiq_unique_jobs/middleware/` - Sidekiq middleware implementations
- `lib/sidekiq_unique_jobs/orphans/` - Orphaned lock cleanup system
- `lib/sidekiq_unique_jobs/web/` - Sidekiq Web UI extension
- `spec/` - RSpec test suite organized by component
- `myapp/` - Example Rails application for testing and development

## Working with Claude in this repo

Commands and agents pin a model tier via frontmatter aliases: `sonnet` for CI/review/TDD specialists, `opus` for orchestration, security, and PR review. Use aliases, not full model IDs, so commands track the latest model in each tier. When spawning subagents for mechanical work (file finding, pattern scans), pass a cheaper model explicitly rather than letting them inherit the session model.

## Common Pitfalls

1. **Lock digest issues**: If uniqueness isn't working as expected, check what's included in the digest (queue, worker class, args). Use `lock_info: true` to debug.

2. **While executing locks**: These won't prevent enqueueing duplicates, only concurrent execution. Often misunderstood by users.

3. **Lock expiration**: `lock_ttl` expires from when lock is created, not from when job finishes. For daily jobs, use `until_expired` with 1.day TTL.

4. **Reaper configuration**: The Lua reaper is faster but can block Redis. Keep `reaper_count` low (≤1000) when using `:lua` reaper. Use `:ruby` reaper (default) for safety.

5. **Testing uniqueness**: Don't test the gem's uniqueness behavior in your app tests. Trust the gem's test suite. Disable uniqueness in your tests with `config.enabled = false`.

6. **Middleware not loaded**: Since v7, middleware must be manually added to Sidekiq configuration. Check initializer follows the README pattern.

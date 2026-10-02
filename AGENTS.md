# AGENTS.md

Project instructions for every agent working in this repo: Claude Code (`CLAUDE.md` imports this
file), Grok, Cursor, Copilot, Codex. Claude-only extras (rules, commands) live under `.claude/` —
see `.claude/rules/` for coding style, git workflow, and testing detail.

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

Command output is condensed by rtk (PreToolUse hook). `.rtk/filters.toml` covers this repo's
`rake` tasks (`rubocop`, `style`, `reek`, `yard` — reek isn't currently a dependency, so its stub
output is boilerplate); every edit to it needs `rtk trust --yes` + `rtk verify`. Write commands in
hook-rewritable shapes: no `for`/subshell wrappers, no `| head` on rtk-handled commands,
`bundle exec rubocop` not `bin/rubocop`.

### Build and Release
```bash
# Run all checks (style, tests, documentation)
bundle exec rake

# Release a new gem version (only for maintainers; see RELEASING.md)
bin/release --dry-run   # what would ship
bin/release             # patch bump; `minor`, `major` or an explicit 9.0.0.alpha3
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

## Working with agents in this repo

**Models.** Sessions run on `opus` (Opus 5.5) with `fable` (Fable 5.1) as the advisor (`.claude/settings.json`). Fable is spent where judgment matters most: `/plan` runs on Fable, the advisor is consulted at decision points (before choosing an approach, a schema or public API, a migration, a dependency, anything irreversible, and when a failure repeats), and the `fable-validator` agent checks every finished implementation before its pull request opens (`/lfg`, Phase 6.5). Commands pin their tier by alias, never by full model ID: `opus` for orchestration, security, full PR review, payments and production debugging; `sonnet` for the implementation specialists and TDD; `haiku` for mechanical scans. Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model. Plan mode cannot take a model of its own: it runs on Opus and asks the advisor.

## Common Pitfalls

1. **Lock digest issues**: If uniqueness isn't working as expected, check what's included in the digest (queue, worker class, args). Use `lock_info: true` to debug.

2. **While executing locks**: These won't prevent enqueueing duplicates, only concurrent execution. Often misunderstood by users.

3. **Lock expiration**: `lock_ttl` expires from when lock is created, not from when job finishes. For daily jobs, use `until_expired` with 1.day TTL.

4. **Reaper configuration**: The Lua reaper is faster but can block Redis. Keep `reaper_count` low (≤1000) when using `:lua` reaper. Use `:ruby` reaper (default) for safety.

5. **Testing uniqueness**: Don't test the gem's uniqueness behavior in your app tests. Trust the gem's test suite. Disable uniqueness in your tests with `config.enabled = false`.

6. **Middleware not loaded**: Since v7, middleware must be manually added to Sidekiq configuration. Check initializer follows the README pattern.

## Labels

Every pull request carries exactly one `type` label and at least one `area`
label from `.github/labels.yml` — never a `status` label. `/plan` labels the
issue, `/lfg` copies the issue's labels onto the PR (or infers them:
`bin/labels infer $(git diff --name-only origin/main...HEAD)`). Labels change in
the manifest and reach GitHub with `bin/labels sync`, never through the UI.
Rules: `.github/LABELS.md`. `bin/labels` + `.github/LABELS.md` are the shared
labels kit (canonical copy in docs-kit): never edit them in place.

## Screenshots on PRs and issues (Web UI changes)

This gem ships a Sidekiq Web UI extension (`lib/sidekiq_unique_jobs/web/`). A change to a Web UI
view, template, or stylesheet ships with before/after pictures **on the PR**, attached from the
terminal. Never a local path, a base64 blob, or "screenshot available on request".

```bash
gh pr create --attach './after.png#Locks tab, digest column' --title … --label <type> --label <area> --body …   # picture in hand already
gh pr comment <n> --attach './after.png#Locks tab, digest column' --body 'Before/after for the digest column.'
gh pr comment <n> --attach ./before.png --attach ./after.png   # repeat the flag, up to 50 files
gh issue comment <n> --attach ./repro.mp4                       # video renders as a player
```

- Quote the whole argument: the alt text has spaces and bare `<`/`>` would redirect. `<file>#<alt text>`
  sets the alt text; without it the filename is used. A body that already references the file
  (`![alt](./after.png)`) gets that reference rewritten to the uploaded asset, so images can sit
  inline; unreferenced attachments are appended at the end.
- `create`, `edit` and `comment` all take `--attach` (all three landed in gh 2.99). Attach at create
  time when the picture already exists; comment when it comes later, as it does after a
  verification run.
- Capture with `agent-browser screenshot <file>` or the Playwright MCP `browser_take_screenshot`.
  Save under the scratchpad, never in the repo.
- No `--attach` flag means an old `gh`: `brew upgrade gh`.

Changes to lock logic, Lua scripts, middleware, or anything without a rendered UI don't need
screenshots.

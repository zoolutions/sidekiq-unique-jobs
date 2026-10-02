# sidekiq-unique-jobs

Prevents duplicate Sidekiq jobs. Uses Redis locks to ensure only one job with the same arguments runs at a time.

[![Build Status](https://github.com/zoolutions/sidekiq-unique-jobs/actions/workflows/rspec.yml/badge.svg?branch=main)](https://github.com/zoolutions/sidekiq-unique-jobs/actions)

📚 **[Full documentation →](https://sidekiq-unique-jobs.zoolutions.llc)** — concepts, use-case guides, and reference.

## Support Me

Want to show me some love for the hard work I do on this gem? You can use the following PayPal link: [https://paypal.me/mhenrixon2](https://paypal.me/mhenrixon2). Any amount is welcome and let me tell you it feels good to be appreciated. Even a dollar makes me super excited about all of this.

## Requirements

- Ruby >= 3.2
- Sidekiq >= 8.0
- Redis >= 6.2 (for LMOVE support)

## Installation

```ruby
gem "sidekiq-unique-jobs", "~> 9.0"
```

## Quick Start

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)
end
```

```ruby
class MyJob
  include Sidekiq::Job

  sidekiq_options lock: :until_executed

  def perform(user_id)
    # Only one job per user_id runs at a time
  end
end
```

That's it. Duplicate jobs are silently dropped by default.

## Lock Types

| Type | Locks at | Unlocks at | Use case |
|------|----------|------------|----------|
| `:until_executing` | Enqueue | Before perform | Prevent duplicate enqueuing |
| `:until_executed` | Enqueue | After perform | Prevent duplicates until job completes |
| `:until_expired` | Enqueue | TTL expiry | Time-based uniqueness (e.g. daily jobs) |
| `:while_executing` | Perform | After perform | Prevent concurrent execution |
| `:until_and_while_executing` | Enqueue + Perform | Before + After perform | Full lifecycle protection |

## Conflict Strategies

When a duplicate is detected, the conflict strategy determines what happens:

| Strategy | Behavior |
|----------|----------|
| `:log` (default) | Log and discard the duplicate |
| `:raise` | Raise `SidekiqUniqueJobs::OnConflict::Raise` |
| `:reject` | Send to dead set |
| `:replace` | Delete the existing job and enqueue the new one |
| `:reschedule` | Schedule the duplicate to run later |

```ruby
sidekiq_options lock: :until_executed,
               on_conflict: :reject

# Or different strategies for client (enqueue) and server (execute):
sidekiq_options lock: :until_and_while_executing,
               on_conflict: { client: :log, server: :reschedule }
```

## Configuration

```ruby
SidekiqUniqueJobs.configure do |config|
  config.lock_ttl          = nil     # Lock expiration in seconds (nil = no expiry)
  config.lock_timeout      = 0       # How long to wait for a lock (0 = don't wait)
  config.lock_prefix       = "uniquejobs"
  config.on_conflict       = nil     # Global default conflict strategy
  config.lock_info         = false   # Store lock metadata (useful for debugging)
  config.enabled           = true    # Disable uniqueness globally
  config.reaper            = :ruby   # Orphaned lock cleanup (:ruby, :lua, true, :none, false)
  config.reaper_count      = 1000    # Max locks to reap per cycle
  config.reaper_interval   = 600     # Seconds between reaper runs
  config.reaper_timeout    = 10      # Max seconds per reaper run
  config.digest_algorithm  = :legacy # :legacy (MD5) or :modern (SHA3-256)
end
```

## Controlling Uniqueness

### Custom Lock Arguments

By default, uniqueness is based on worker class, queue, and all arguments. To customize:

```ruby
class MyJob
  include Sidekiq::Job

  sidekiq_options lock: :until_executed,
                 lock_args_method: ->(args) { [args.first] }

  def perform(user_id, timestamp)
    # Only user_id determines uniqueness, timestamp is ignored
  end
end
```

### Lock TTL

```ruby
sidekiq_options lock: :until_expired,
               lock_ttl: 3600  # Lock expires after 1 hour
```

### Uniqueness Across Queues

```ruby
sidekiq_options lock: :until_executed,
               unique_across_queues: true  # Same args on different queues = duplicate
```

## ReliableFetch

v9 includes an optional reliable fetch strategy that provides crash recovery and lock-aware job acknowledgment:

```ruby
Sidekiq.configure_server do |config|
  config[:fetch_class] = SidekiqUniqueJobs::Fetch::Reliable
end
```

Features:
- **Atomic LMOVE**: Jobs move from queue to per-process working list atomically
- **Crash recovery**: On startup, recovers jobs from dead worker processes
- **Lock-aware acknowledge**: Confirms lock cleanup after job completion
- **Lock-preserving requeue**: During shutdown, locks persist for requeued jobs

## Web UI

Add to your routes:

```ruby
require "sidekiq_unique_jobs/web"
```

This adds a **Locks** tab to the Sidekiq Web UI where you can browse, filter, and delete locks.

## Testing

Disable uniqueness in your tests:

```ruby
SidekiqUniqueJobs.config.enabled = false
```

Or use `Sidekiq::Testing` modes:

```ruby
Sidekiq::Testing.inline! do
  # Jobs execute immediately, uniqueness still enforced
end
```

## Upgrading from v8

v9 automatically migrates v8 lock data on first startup. No manual steps required.

Key changes:
- **Redis keys**: 2 per lock (down from 13). Only `digest:LOCKED` hash and `uniquejobs:digests` sorted set.
- **Sidekiq 8+ only**: Dropped Sidekiq 7 support.
- **Ruby 3.2+ only**: Dropped older Ruby support.
- **Changelog removed**: Use the [reflection system](https://github.com/zoolutions/sidekiq-unique-jobs#reflections) for lock event observability.
- **Expiring locks unified**: No separate `expiring_digests` sorted set. TTL-based locks use the same `digests` ZSET with expiry time as score.

## Reflections

Observe lock lifecycle events without modifying behavior:

```ruby
SidekiqUniqueJobs.reflect do |on|
  on.locked { |job| logger.info("Locked: #{job['class']}") }
  on.unlocked { |job| logger.info("Unlocked: #{job['class']}") }
  on.lock_failed { |job| logger.warn("Lock failed: #{job['class']}") }
  on.execution_failed { |job| logger.error("Execution failed: #{job['class']}") }
end
```

## Sidekiq Pro and Super Fetch
 * When using sidekiq pro with the super fetch feature you may see jobs "dissappear" after deployments and or scale
   events in your environment, this is particularly noticeable when using Batches, they will appear to be in a "stuck"
   state.
 * A common cause of this is that the combination of `lock:` configuration (usually with `:until_and_while_executing`
   combined with a longish `:lock_ttl`). When super fetch retrieves the job and tries to reenqueue the lock still exists
   and your job gets dropped silently (unless you have `:raise` `:on_conflict`).
 * Use a hook similar to the following to delete the locks and allow super fetch to complete recovery.
```ruby
config.super_fetch! do |jobstr, _pill|
  job = JSON.parse(jobstr)
  if job["lock_digest"]
    begin
      SidekiqUniqueJobs::Locksmith.new(job).unlock

      puts "Job [#{job["jid"]}] unlocked by superfetch"
    rescue => error
      puts error
    end
  end
  puts "Job [#{job["jid"]}] recovered by superfetch"
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Run tests (`bundle exec rspec`)
4. Run linter (`bundle exec rubocop`)
5. Commit and push
6. Create a Pull Request

## License

MIT

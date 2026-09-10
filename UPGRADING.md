# Upgrading

## v9.0.0

Full guide: **[Upgrading to v9](https://sidekiq-unique-jobs.zoolutions.llc/docs/upgrading-to-v9)**
(source: `docs/app/views/docs/pages/upgrading_to_v9.rb`).

### Requirements

- Ruby >= 3.2
- Sidekiq >= 8.0
- Redis >= 6.2

### What happens automatically

On first boot, v9 migrates v8 lock data in place:

- Collapses the old multi-key lock model into two keys per lock (`digest:LOCKED` + `uniquejobs:digests`)
- Merges `uniquejobs:expiring_digests` into `uniquejobs:digests`
- Removes obsolete v8 keys (`QUEUED`, `PRIMED`, `INFO`, …)

No migration script to run.

### Behavioral changes to know about

| Area | v8 | v9 |
|------|----|----|
| Lock acquisition | Could wait when `lock_timeout > 0` | Always non-blocking; use an `on_conflict` strategy (e.g. `:reschedule`) instead of waiting |
| Reaper | `:ruby` or `:lua` | Ruby only. `:lua` is accepted but ignored (deprecation warning) |
| Changelog history | Stored in Redis | Removed — use [reflections](https://sidekiq-unique-jobs.zoolutions.llc/docs/reflections) |
| `until_expired` digests | Separate `expiring_digests` ZSET | Same `digests` ZSET; score is expiry time in **seconds** |

### Known limitations (intentional in v9)

- **`UntilExecuting`**: if unlock fails on the server, the job still runs. Unlock failure is unusual (wrong JID holding the lock).
- **`UntilAndWhileExecuting`**: if the client unlock fails before the runtime lock, the job is skipped (Sidekiq marks it successful) and `:unlock_failed` is reflected — it is not raised.
- **ReliableFetch** is optional. Lock-lapse detection / lock-aware ack only apply when you set `config[:fetch_class] = SidekiqUniqueJobs::Fetch::Reliable`.
- **`:duplicate` reflection** is registered for compatibility but is not dispatched; prefer `:lock_failed`.

### Cleanup after upgrading from early alphas

If you ran `9.0.0.alpha*` with `:until_expired` locks, some digests may have been written with millisecond-based scores. v9’s reaper sweeps those once their `:LOCKED` hash has expired. To force a cleanup:

```ruby
SidekiqUniqueJobs::Digests.new.delete_by_pattern("*", count: 10_000)
```

Only do this if you are sure no live unique jobs should remain locked.

---

## v7.1.0

### Reflection API

SidekiqUniqueJobs do not log by default anymore. Instead I have a reflection API that I shamelessly borrowed from Rpush.

To use the new notification/reflection system please define them as follows in an initializer of your choosing.

```ruby
SidekiqUniqueJobs.reflect do |on|
  # Only raised when you have defined such a callback
  on.after_unlock_callback_failed do |job_hash|
    logger.warn(job_hash.merge(message: "Unlock callback failed"))
  end

  # This job is skipped because it is a duplicate
  on.duplicate do |job_hash|
    logger.warn(job_hash.merge(message: "Duplicate Job"))
  end

  # This means your code broke and we caught the exception to provide this reflection for you.
  on.execution_failed do |job_hash, exception = nil|
    message = "Execution failed"
    message = message + "(#{exception.message})" if exception
    logger.warn(job_hash.merge(message: message))
  end

  # Failed to acquire lock in a timely fashion
  on.lock_failed do |job_hash|
    logger.warn(job_hash.merge(message: "Lock failed"))
  end

  # In case you want to collect metrics
  on.locked do |job_hash|
    logger.debug(job_hash.merge(message: "Lock success"))
  end

  # When your conflict strategy is to reschedule and it failed
  on.reschedule_failed do |job_hash|
    logger.debug(job_hash.merge(message: "Reschedule failed"))
  end

  # When your conflict strategy is to reschedule and it was successful
  on.rescheduled do |job_hash|
    logger.debug(job_hash.merge(message: "Reschedule success"))
  end

  # You asked to wait for a lock to be achieved but we timed out waiting
  on.timeout do |job_hash|
    logger.warn(job_hash.merge(message: "Oh no! Timeout!! Timeout!!"))
  end

  # The current worker isn't part of this sidekiq servers workers
  on.unknown_sidekiq_worker do |job_hash|
    logger.warn(job_hash.merge(message: "WAT!? Why? What is this worker?"))
  end

  # Unlock failed! Not good
  on.unlock_failed do |job_hash|
    logger.warn(job_hash.merge(message: "Unlock failed"))
  end

  # Unlock was successful, perhaps mostly interesting for metrics
  on.unlocked do |job_hash|
    logger.warn(job_hash.merge(message: "Unlock success"))
  end
end
```

You don't need to configure them all. Some of them are just informational, some of them more for metrics and a couple of them (failures, timeouts) might be of real interest.

I leave it up to you to decided what to do about it.

### Reaper Resurrector

In [#604](https://github.com/mhenrixon/sidekiq-unique-jobs/pull/604) a reaper resurrector was added. This is configured by default so that if the current reaper process dies, another one kicks off again.

With the recent fixes in [#616](https://github.com/mhenrixon/sidekiq-unique-jobs/pull/616) there should be even less need for reaping.

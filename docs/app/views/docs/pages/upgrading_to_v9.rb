# frozen_string_literal: true

class Views::Docs::Pages::UpgradingToV9 < DocsUI::Page
  title "Upgrading to v9"
  eyebrow "Migrate"

  def lead = "v9 is a ground-up rewrite that migrates your existing v8 locks automatically on first startup — no scripts to run, no downtime to plan."

  def content
    the_short_version
    breaking_changes
    what_the_migration_does
    two_keys_now
    changelog_removed
    checklist
  end

  private

  def the_short_version
    DocsUI::Section("The short version", description: "Bump the gem, re-check your initializer, boot.") do
      md <<~'MD'
        Most of v9 lives below the surface. The public API you write in your
        workers — `sidekiq_options lock: :until_executed`, conflict strategies,
        `lock_ttl`, `lock_args_method` — is unchanged. What changed is the
        machinery underneath: the Redis data model, the fetch loop, and the
        minimum versions of Ruby and Sidekiq.

        Bump the gem and boot your app:
      MD

      DocsUI::Code(<<~RUBY)
        # Gemfile
        gem "sidekiq-unique-jobs", "~> 9.0"
      RUBY

      md <<~'MD'
        On the first boot, v9 upgrades any locks written by v8 into the new
        format for you. There is nothing else to run.
      MD

      DocsUI::Callout(:note) do
        plain "There is no data migration script to run. v9 migrates your v8 lock data on the first startup, in place. Deploy it like any other gem bump."
      end
    end
  end

  def breaking_changes
    DocsUI::Section("Breaking changes", description: "The things that can stop your app from booting.") do
      md <<~'MD'
        - **Sidekiq 8.0 or newer only.** v9 drops support for every earlier
          Sidekiq release. If you are on Sidekiq 7 or below, upgrade Sidekiq
          first, then upgrade this gem.
        - **Ruby 3.2 or newer only.** Older Rubies are no longer supported.
        - **The changelog history feature is gone.** v8 recorded a per-lock
          event log; v9 removes it in favor of the reflection system. See the
          "Changelog history is gone" section below.
        - **The Redis data model changed.** A lock is now two keys instead of up
          to thirteen. The upgrade rewrites your existing locks into the new
          shape automatically — you do not touch Redis yourself.

        None of these require code changes in your workers. The two that can
        block a boot are the version floors: pin Ruby to 3.2+ and Sidekiq to
        8.0+ before you deploy.
      MD
    end
  end

  def what_the_migration_does
    DocsUI::Section("What happens on the first boot") do
      md <<~'MD'
        When a v9 process starts, it runs a one-time upgrade over the locks left
        behind by v8. It reads the old multi-key lock structures out of Redis and
        rewrites each one into the v9 two-key format, preserving which jobs hold
        which locks. Jobs that are already enqueued or in flight stay unique
        across the transition — you do not lose locks and you do not get a burst
        of duplicates.

        Because the migration is automatic and in place, the rollout is a normal
        deploy: replace the gem, restart your Sidekiq processes, done. If you run
        a fleet, the first process to come up on v9 performs the upgrade and the
        rest join the already-migrated data.
      MD
    end
  end

  def two_keys_now
    DocsUI::Section("Two Redis keys per lock", description: "Down from as many as thirteen.") do
      md <<~'MD'
        v8 spread a single lock across several Redis keys — separate structures
        for the lock, its queue, its metadata, its changelog, and a distinct
        sorted set for expiring locks. v9 collapses all of that into two keys:
      MD

      DocsUI::Code(<<~TEXT, lexer: :text)
        <digest>:LOCKED       # Hash  — the job IDs holding this lock, with metadata
        uniquejobs:digests    # ZSet  — a global index of every active lock
      TEXT

      md <<~'MD'
        There is no longer a separate `expiring_digests` sorted set. TTL locks —
        the ones created by `:until_expired` — now live in the same
        `uniquejobs:digests` index as every other lock, with their expiry time
        stored as the score. One index, one code path, whether or not a lock has
        a TTL. Fewer keys means less Redis memory per lock and simpler,
        cheaper reaping of orphans.
      MD
    end
  end

  def changelog_removed
    DocsUI::Section("Changelog history is gone", description: "Reflections replace it.") do
      md <<~'MD'
        v8 kept a rolling changelog of lock events in Redis. v9 removes it. If you
        relied on that history to see when locks were acquired, released, or
        contended, move to the reflection system — it hands you the same events
        as they happen, and you send them wherever you already send metrics and
        logs instead of storing them in Redis.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.reflect do |on|
          on.locked        { |job_hash| StatsD.increment("uniquejobs.locked") }
          on.lock_failed   { |job_hash| StatsD.increment("uniquejobs.lock_failed") }
          on.unlocked      { |job_hash| StatsD.increment("uniquejobs.unlocked") }
        end
      RUBY

      md <<~'MD'
        Reflections cover fourteen lock-lifecycle events — locked, unlocked,
        lock_failed, timeout, duplicate, execution_failed, and more. See
        [Observability](/docs/observability) for the full picture and
        [Reflections](/docs/reflections) for the complete event list.
      MD
    end
  end

  def checklist
    DocsUI::Section("Upgrade checklist") do
      md <<~'MD'
        1. **Raise your version floors.** Ruby 3.2+ and Sidekiq 8.0+ are
           required. Upgrade those first if you are behind.
        2. **Bump the gem** to `~> 9.0` and run `bundle install`.
        3. **Re-check your initializer.** The middleware is still not loaded
           automatically — confirm your Sidekiq configuration matches the current
           [Installation](/docs/installation) guide.
        4. **Replace any changelog-history usage** with the reflection system —
           see [Reflections](/docs/reflections).
        5. **Deploy and boot.** The first v9 process migrates your v8 locks in
           place. No migration script, no manual Redis surgery.
      MD

      DocsUI::Callout(:tip) do
        plain "Consider enabling ReliableFetch while you are here — v9 makes it opt-in with a single config line so jobs survive a crashed worker. See "
        a(href: "/docs/reliablefetch") { "ReliableFetch" }
        plain "."
      end
    end
  end
end

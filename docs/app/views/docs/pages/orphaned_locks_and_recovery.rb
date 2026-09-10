# frozen_string_literal: true

class Views::Docs::Pages::OrphanedLocksAndRecovery < DocsUI::Page
  title "Orphaned locks and recovery"
  eyebrow "Concepts"

  def lead = "When a process crashes while holding a lock, the reaper finds the stranded lock and releases it so future jobs aren't blocked forever."

  def content
    how_locks_orphan
    the_reaper
    configuring_the_reaper
    reference
    the_resurrector
    startup_recovery
  end

  private

  def how_locks_orphan
    DocsUI::Section("How a lock becomes orphaned") do
      md <<~'MD'
        A healthy lock has a clear life: it's acquired, the job runs, the lock is
        released. But a Sidekiq process can die at the worst moment — an OOM kill,
        a `SIGKILL`, a crashed host — after it acquired a lock but before it got a
        chance to clean up.

        The lock is still sitting in Redis, but the job that owned it is gone. It
        will never finish, so it will never release. That's an **orphaned lock**:
        a lock with no live job behind it. Left alone, a duplicate of that job can
        be blocked indefinitely.
      MD

      DocsUI::Callout(:note) do
        plain "Locks with a "
        a(href: "/docs/configuration-reference") { "lock_ttl" }
        plain " eventually expire on their own, so a TTL is a safety net against orphans. Locks without a TTL never expire — for those, the reaper is the only thing that cleans up after a crash."
      end
    end
  end

  def the_reaper
    DocsUI::Section("What the reaper does", description: "A background thread that removes locks with no live job.") do
      md <<~'MD'
        The reaper is a background thread that wakes up on an interval, scans the
        `uniquejobs:digests` index, and asks a simple question of each lock: is
        there a live job that owns you? A job counts as live if it's sitting in a
        queue, scheduled, retrying, or actively being processed by a worker that's
        still checking in. If none of those are true, the lock is orphaned and the
        reaper deletes it.

        You don't start it or call it — it runs inside the Sidekiq **server**
        process, set up for you by `SidekiqUniqueJobs::Server.configure` in your
        initializer.
      MD

      DocsUI::Code(<<~RUBY)
        # config/initializers/sidekiq.rb
        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add SidekiqUniqueJobs::Middleware::Client
          end
          config.server_middleware do |chain|
            chain.add SidekiqUniqueJobs::Middleware::Server
          end
          SidekiqUniqueJobs::Server.configure(config) # starts the reaper
        end
      RUBY
    end
  end

  def configuring_the_reaper
    DocsUI::Section("Choosing a reaper") do
      md <<~'MD'
        `config.reaper` turns orphan cleanup on or off:

        - **`:ruby`** / **`true`** (default) — scans in Ruby, in batches, without
          holding Redis for long stretches.
        - **`:none`** / **`false`** — disables the reaper. Only sensible if every
          lock you use carries a `lock_ttl`, so orphans expire on their own.
        - **`:lua`** — removed in v9. Accepted for compatibility but ignored; a
          deprecation warning is emitted and the Ruby reaper runs instead.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.reaper          = :ruby # :ruby / true, or :none / false
          config.reaper_count    = 1000  # max locks reaped per cycle
          config.reaper_interval = 600   # seconds between runs
          config.reaper_timeout  = 10    # max seconds a single run may take
        end
      RUBY
    end
  end

  def reference
    DocsUI::Section("Reaper settings") do
      md <<~'MD'
        All of these are set inside a `SidekiqUniqueJobs.configure` block.
      MD

      DocsUI::PropTable([
        [ "reaper", "Symbol / false", ":ruby", "Orphan cleanup: :ruby/true (default), or :none/false to disable. :lua is ignored (deprecated)." ],
        [ "reaper_count", "Integer", "1000", "Maximum number of orphaned locks removed in a single cycle." ],
        [ "reaper_interval", "Integer", "600", "Seconds to wait between reaper runs." ],
        [ "reaper_timeout", "Integer", "10", "Maximum seconds a single reaper run is allowed to take before it stops." ]
      ])
    end
  end

  def the_resurrector
    DocsUI::Section("The resurrector") do
      md <<~'MD'
        Only one Sidekiq process holds the reaper mutex at a time. Every other
        process runs a lightweight **resurrector** that watches that mutex and
        takes over if the holder dies (for example after an OOM kill). This is
        always on when the reaper itself is enabled — you do not need a separate
        config flag.
      MD
    end
  end

  def startup_recovery
    DocsUI::Section("Recovery at startup") do
      md <<~'MD'
        The reaper handles orphaned locks *while your fleet is running*. It's the
        general-purpose cleanup, and for most apps it's all you need.

        If you also want jobs themselves — not just their locks — to survive a
        crashed process, opt into [ReliableFetch](/docs/reliablefetch). It moves
        each job to a per-process working list as it's fetched and, on startup,
        recovers any jobs abandoned by processes that died, re-enqueuing them with
        their lock intact so they stay unique. The reaper and ReliableFetch are
        complementary: one reclaims stranded locks, the other reclaims stranded
        jobs.
      MD

      DocsUI::Callout(:tip) do
        plain "Every knob on this page lives in the "
        a(href: "/docs/configuration-reference") { "Configuration reference" }
        plain ", alongside the rest of the global settings."
      end
    end
  end
end

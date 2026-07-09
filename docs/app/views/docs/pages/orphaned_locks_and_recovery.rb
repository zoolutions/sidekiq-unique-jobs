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
        `config.reaper` picks which implementation runs. There are two, plus an
        off switch:

        - **`:ruby`** (default) — does the scanning in Ruby. It's the safe choice:
          it works in batches and can never hold Redis long enough to block other
          clients. Use this unless you have a specific reason not to.
        - **`:lua`** — does the scanning inside a single Lua script. It's faster,
          but Lua runs to completion with Redis effectively single-threaded, so a
          large scan briefly blocks every other Redis command.
        - **`:none`** or **`false`** — disables the reaper entirely. Only sensible
          if every lock you use carries a `lock_ttl`, so orphans expire on their own.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.reaper          = :ruby # :ruby (default), :lua, or :none / false
          config.reaper_count    = 1000  # max locks reaped per cycle
          config.reaper_interval = 600   # seconds between runs
          config.reaper_timeout  = 10    # max seconds a single run may take
        end
      RUBY

      DocsUI::Callout(:warning) do
        plain "With the :lua reaper, keep reaper_count low (1000 or less). The scan runs as one Lua script and blocks Redis while it works — a large count can stall every other client for the duration of the sweep. The :ruby reaper has no such limit."
      end
    end
  end

  def reference
    DocsUI::Section("Reaper settings") do
      md <<~'MD'
        All of these are set inside a `SidekiqUniqueJobs.configure` block.
      MD

      DocsUI::PropTable([
        [ "reaper", "Symbol / false", ":ruby", "Which reaper runs: :ruby (safe, cannot block Redis), :lua (faster, briefly blocks Redis), or :none / false to disable." ],
        [ "reaper_count", "Integer", "1000", "Maximum number of orphaned locks removed in a single cycle." ],
        [ "reaper_interval", "Integer", "600", "Seconds to wait between reaper runs." ],
        [ "reaper_timeout", "Integer", "10", "Maximum seconds a single reaper run is allowed to take before it stops." ],
        [ "reaper_resurrector_enabled", "Boolean", "false", "Watch the reaper thread and restart it if it dies." ],
        [ "reaper_resurrector_interval", "Integer", "3600", "Seconds between resurrector checks on the reaper thread." ]
      ])
    end
  end

  def the_resurrector
    DocsUI::Section("The resurrector") do
      md <<~'MD'
        The reaper is a long-lived thread, and threads can die — an unhandled
        error deep in a scan, for instance. If the reaper thread dies quietly,
        orphaned locks would pile up unnoticed.

        The **resurrector** guards against that. It's a second, lightweight thread
        that periodically checks whether the reaper is still alive and restarts it
        if it isn't. It's **off by default**; turn it on if you want the reaper to
        be self-healing.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.reaper_resurrector_enabled  = true # off by default
          config.reaper_resurrector_interval = 3600 # seconds between checks
        end
      RUBY
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

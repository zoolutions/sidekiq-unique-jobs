# frozen_string_literal: true

class Views::Docs::Pages::Observability < DocsUI::Page
  title "Observability"
  eyebrow "Concepts"

  def lead = "See locks working: fan every lock event out to your metrics and logs with reflections, add per-lock debug metadata, and browse live locks in the Web UI."

  def content
    reflections
    reflection_example
    lock_info
    web_ui
  end

  private

  def reflections
    DocsUI::Section("Reflections", description: "Fan every lock event out to StatsD, your logger, or an error tracker.") do
      md <<~'MD'
        A lock is invisible by default — it acquires, holds, and releases without
        telling you anything. Reflections are the observability seam: the gem
        emits a named event at every interesting moment, and you attach whatever
        you want to it. Metrics, structured logs, error-tracker breadcrumbs — all
        of it hangs off one registration block.

        Register handlers with `SidekiqUniqueJobs.reflect`. It yields an `on`
        object; you call one method per event and pass a block that runs when
        that event fires. **The block is required** — registering an event
        without one raises `NoBlockGiven`.
      MD

      DocsUI::Code(<<~RUBY)
        # config/initializers/sidekiq_unique_jobs.rb
        SidekiqUniqueJobs.reflect do |on|
          on.locked do |job_hash|
            StatsD.increment("uniquejobs.locked")
          end
        end
      RUBY

      md <<~'MD'
        Each handler receives the Sidekiq job hash (`job_hash["class"]`,
        `job_hash["args"]`, `job_hash["jid"]`, and so on). A few events pass a
        second argument — `execution_failed`, for instance, also hands you the
        exception that was raised.

        There are fourteen events in all: `locked`, `lock_failed`, `unlocked`,
        `unlock_failed`, `timeout`, `duplicate`, `execution_failed`,
        `after_unlock_callback_failed`, `rescheduled`, `reschedule_failed`,
        `uniqueness_lapsed`, `unknown_sidekiq_worker`, `debug`, and `error`. The
        full list with every signature lives in the
        [Reflections](/docs/reflections) reference.
      MD
    end
  end

  def reflection_example
    DocsUI::Section("A worked example", description: "Wire the four events you'll actually watch.") do
      md <<~'MD'
        In practice you care about a handful of events: did the lock succeed, did
        it fail, did it release, and did the job blow up while holding it. Here's
        a complete initializer wiring those to StatsD counters and a logger.
      MD

      DocsUI::Code(<<~'RUBY')
        # config/initializers/sidekiq_unique_jobs.rb
        SidekiqUniqueJobs.reflect do |on|
          on.locked do |job_hash|
            StatsD.increment("uniquejobs.locked", tags: ["worker:#{job_hash["class"]}"])
          end

          on.lock_failed do |job_hash|
            StatsD.increment("uniquejobs.lock_failed", tags: ["worker:#{job_hash["class"]}"])
            Sidekiq.logger.warn("lock failed for #{job_hash["class"]} (#{job_hash["jid"]})")
          end

          on.unlocked do |job_hash|
            StatsD.increment("uniquejobs.unlocked", tags: ["worker:#{job_hash["class"]}"])
          end

          on.execution_failed do |job_hash, exception|
            StatsD.increment("uniquejobs.execution_failed", tags: ["worker:#{job_hash["class"]}"])
            Sidekiq.logger.error("#{job_hash["class"]} raised #{exception.class}: #{exception.message}")
          end
        end
      RUBY

      md <<~'MD'
        You don't have to register every event — only the ones you register run.
        Everything else stays a no-op, so there's no cost to watching just four.

        A `lock_failed` counter climbing steadily is your signal that real
        duplicates are being caught. A single spike after a deploy usually means
        something is enqueuing the same job in a loop.
      MD

      DocsUI::Callout(:tip) do
        plain "Reflection handlers run inline in the middleware. Keep them fast — increment a counter, write a log line. Push slow work (an HTTP call, a database write) onto a background thread or queue so a slow metrics sink never delays a job."
      end
    end
  end

  def lock_info
    DocsUI::Section("lock_info: debug metadata", description: "Store the why-and-when alongside each lock.") do
      md <<~'MD'
        Reflections tell you what happened over time. When you need to inspect a
        *single* lock — why does this digest still exist, who took it, when —
        turn on `lock_info` for the worker.
      MD

      DocsUI::Code(<<~RUBY)
        class ChargeCustomerJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, lock_info: true

          def perform(customer_id)
            # ...
          end
        end
      RUBY

      md <<~'MD'
        With `lock_info: true`, the gem stores metadata about the lock in Redis —
        the worker, the queue, the arguments, the lock type, timeouts, and the
        timestamp it was taken. That metadata is what the Web UI renders when you
        click into a lock, and it's what makes an orphaned lock legible instead of
        an opaque digest.

        It costs an extra write per lock, so it's off by default
        (`config.lock_info` is `false`). Turn it on per worker while you're
        debugging, or globally in your configuration block:
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.lock_info = true
        end
      RUBY

      DocsUI::Callout(:note) do
        plain "lock_info is diagnostic metadata — it never changes which jobs are considered duplicates. Uniqueness is always decided by the digest (worker class, queue, and arguments), whether or not lock_info is on."
      end
    end
  end

  def web_ui
    DocsUI::Section("The Web UI Locks tab", description: "Browse, filter, and delete live locks.") do
      md <<~'MD'
        For an at-a-glance view of every lock currently held, mount the Web UI
        extension. Requiring it adds a **Locks** tab to the standard Sidekiq Web
        UI.
      MD

      DocsUI::Code(<<~RUBY)
        # config/routes.rb (or wherever you mount Sidekiq::Web)
        require "sidekiq/web"
        require "sidekiq_unique_jobs/web"

        Rails.application.routes.draw do
          mount Sidekiq::Web, at: "/sidekiq"
        end
      RUBY

      md <<~'MD'
        The Locks tab lists every active digest. You can filter to find a specific
        lock, click through to see its details (richest when `lock_info` is on),
        and delete a lock by hand — the escape hatch for a lock that's genuinely
        stuck and shouldn't wait for the reaper.

        Reaching for the delete button often means a process crashed without
        cleaning up. That's exactly what the reaper handles automatically — see
        [Orphaned locks](/docs/orphaned-locks).
      MD
    end
  end
end

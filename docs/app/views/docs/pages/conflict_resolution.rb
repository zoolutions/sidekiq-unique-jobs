# frozen_string_literal: true

class Views::Docs::Pages::ConflictResolution < DocsUI::Page
  title "Conflict resolution"
  eyebrow "Concepts"

  def lead = "When a lock is already held, the conflict strategy decides what happens to the duplicate — drop it, retry it, reject it, replace the original, or reschedule it."

  def content
    what_is_a_conflict
    the_five_strategies
    client_vs_server
    global_default
    examples
    where_to_go
  end

  private

  def what_is_a_conflict
    DocsUI::Section("What a conflict is") do
      md <<~'MD'
        A **conflict** happens when a job tries to acquire a lock that another
        copy already holds. The lock type decides *when* the lock is held; the
        conflict strategy decides what happens to the copy that arrives while
        it's held.

        By default the duplicate is simply **logged and discarded** — the second
        `perform_async` returns without enqueuing anything. That's the right
        behavior most of the time: a double-clicked button or a webhook that
        fires twice shouldn't produce two jobs. But sometimes you want the
        duplicate to survive: retried later, replaced, or sent somewhere you can
        inspect it. That's what the strategy chooses.
      MD

      DocsUI::Callout(:note) do
        plain "A duplicate is only a conflict while the lock is held. Once the lock is released, the same arguments enqueue normally again — the strategy only fires during contention."
      end
    end
  end

  def the_five_strategies
    DocsUI::Section("The five strategies", description: "Set with on_conflict: on the worker.") do
      md <<~'MD'
        There are five built-in strategies. `:log` is the effective default when
        you don't set `on_conflict`.
      MD

      DocsUI::PropTable([
        [ "`:log`", "Symbol", "default", "Log the conflict and discard the duplicate. Nothing is enqueued." ],
        [ "`:raise`", "Symbol", "—", "Raise an error so Sidekiq retries the job later." ],
        [ "`:reject`", "Symbol", "—", "Push the duplicate to the Dead set for later inspection." ],
        [ "`:replace`", "Symbol", "—", "Delete the existing job and lock, then enqueue the new one." ],
        [ "`:reschedule`", "Symbol", "—", "Re-enqueue the duplicate to run later, after the lock clears." ]
      ])

      DocsUI::Code(<<~RUBY)
        class ExportReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, on_conflict: :log

          def perform(account_id)
            # A second export for the same account_id, while the first is
            # still locked, is logged and dropped.
          end
        end
      RUBY

      md <<~'MD'
        `:reschedule` and `:reject` are the two you reach for most often once the
        default no longer fits — see [Retry conflicts later](/docs/retry-conflicts-later)
        and [Only the latest matters](/docs/only-the-latest-matters) for the full
        patterns.
      MD
    end
  end

  def client_vs_server
    DocsUI::Section("Client conflicts vs server conflicts", description: "Where the conflict happens decides which strategy runs.") do
      md <<~'MD'
        A lock can be contended in two different places, and each has its own
        strategy:

        - **Client conflicts** happen at *enqueue* time, in the client
          middleware. Client-side locks (`:until_executing`, `:until_executed`,
          `:until_expired`) run their strategy here.
        - **Server conflicts** happen at *execution* time, in the server
          middleware. `:while_executing` locks conflict on the server, because a
          `while_executing` lock is only about preventing concurrent execution —
          it never blocks the enqueue.

        A single symbol applies to whichever side the lock uses. But you can split
        it, giving the client and the server different behavior:
      MD

      DocsUI::Code(<<~RUBY)
        class SyncInventoryJob
          include Sidekiq::Job

          # Drop duplicate enqueues quietly, but if two copies somehow reach
          # execution at once, reschedule the loser instead of dropping it.
          sidekiq_options lock: :until_and_while_executing,
                          on_conflict: { client: :log, server: :reschedule }

          def perform(warehouse_id)
            # ...
          end
        end
      RUBY

      md <<~'MD'
        This split form only matters for locks that have both a client and a
        server phase (like `:until_and_while_executing`). For a purely
        client-side or purely server-side lock, a single symbol is enough.
      MD

      DocsUI::Callout(:tip) do
        plain "The while_executing_reject lock is exactly a while_executing lock with the server strategy forced to :reject — a shorthand for the common case."
      end
    end
  end

  def global_default
    DocsUI::Section("Setting a global default") do
      md <<~'MD'
        You can set a default strategy for every worker that doesn't specify its
        own. It's `nil` by default, which means "fall back to per-worker
        configuration" — and with no per-worker value either, `:log` applies.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.on_conflict = :reschedule
        end
      RUBY

      md <<~'MD'
        A worker's own `on_conflict:` always wins over the global default, so you
        can set a sensible default and override it only where it matters.
      MD
    end
  end

  def examples
    DocsUI::Section("Two worked examples") do
      md <<~'MD'
        ### Reschedule an overlapping cron job

        A job that runs on a schedule can tick again before the previous run has
        finished. `:reschedule` re-enqueues the overlapping copy so it runs once
        the lock clears, instead of silently dropping it.
      MD

      DocsUI::Code(<<~RUBY)
        class NightlyBillingJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, on_conflict: :reschedule

          def perform
            # If the previous nightly run is still going, this tick is
            # re-enqueued to run once the lock is released.
          end
        end
      RUBY

      md <<~'MD'
        ### Reject a duplicate webhook

        A provider that retries a webhook can deliver the same event twice. With
        `:reject`, the duplicate goes to the Dead set — nothing runs twice, and
        you keep a record you can inspect or replay.
      MD

      DocsUI::Code(<<~RUBY)
        class ProcessWebhookJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, on_conflict: :reject

          def self.lock_args(args)
            [args.first["event_id"]]
          end

          def perform(payload)
            # Duplicate deliveries of the same event_id are rejected to the
            # Dead set instead of processed twice.
          end
        end
      RUBY
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[Retry conflicts later](/docs/retry-conflicts-later)** — the full
          `:reschedule` and `:raise` patterns for work that must eventually run.
        - **[Only the latest matters](/docs/only-the-latest-matters)** — when
          `:replace` is the right call for superseding an in-flight job.
        - **[Observability](/docs/observability)** — the reflections that fire on
          conflicts (`duplicate`, `rescheduled`, `reschedule_failed`, `timeout`),
          so you can measure how often they happen.
      MD
    end
  end
end

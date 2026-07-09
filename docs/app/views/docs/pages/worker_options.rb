# frozen_string_literal: true

class Views::Docs::Pages::WorkerOptions < DocsUI::Page
  title "Worker options"
  eyebrow "Reference"

  def lead = "Every per-worker key you can pass to sidekiq_options, plus the lock-type and conflict-strategy symbols they accept."

  def content
    options_table
    lock_types
    conflict_strategies
    everything_together
  end

  private

  def options_table
    DocsUI::Section("sidekiq_options keys", description: "Set these per worker; only lock is required.") do
      md <<~'MD'
        Uniqueness is configured on the worker with `sidekiq_options`. Only `lock:`
        is required — it names the [lock type](/docs/choosing-a-lock-type) and
        turns uniqueness on. Everything else tunes how the lock is keyed, how long
        it lives, and what happens when a duplicate loses the race. Locks in v9 are
        non-blocking: a contended job never waits — it fails its one attempt and the
        conflict strategy fires immediately.
      MD

      DocsUI::PropTable([
        [ "lock", "Symbol", "—", "The lock type. Required to enable uniqueness. See the lock-type table below." ],
        [ "lock_ttl", "Integer (seconds)", "nil", "How long the lock lives in Redis, measured from when it is created — not from when the job finishes." ],
        [ "lock_timeout", "Integer (seconds)", "0", "Parsed and stored in lock metadata, but inert for acquisition in v9's non-blocking model — it does not make a job wait. A contended lock fails its single attempt and the conflict strategy runs immediately." ],
        [ "lock_limit", "Integer", "1", "How many concurrent holders of the same digest are allowed before a job is treated as a duplicate." ],
        [ "on_conflict", "Symbol or Hash", "nil", "What to do with a duplicate. A single symbol, or {client:, server:} to split the two sides. See the strategy table below." ],
        [ "lock_args_method", "Symbol or Proc", "nil", "Selects which arguments matter for uniqueness. A symbol naming a class method, or a lambda; returns the subset of args to key on." ],
        [ "unique_across_queues", "Boolean", "false", "Ignore the queue when computing the digest, so the same args on any queue count as a duplicate." ],
        [ "unique_across_workers", "Boolean", "false", "Ignore the worker class when computing the digest, so different workers with the same args count as duplicates." ],
        [ "lock_info", "Boolean", "false", "Store extra debugging metadata about the lock (who, when, which arguments) for inspection in the Web UI." ],
        [ "lock_prefix", "String", "\"uniquejobs\"", "Override the Redis key prefix for this worker's locks." ]
      ])

      DocsUI::Callout(:note) do
        plain "Any option omitted here falls back to its global default. Set those defaults once in your initializer — see "
        a(href: "/docs/configuration-reference") { "Configuration reference" }
        plain "."
      end
    end
  end

  def lock_types
    DocsUI::Section("Lock types and their aliases", description: "Pass any alias to lock: — they map to the same behavior.") do
      md <<~'MD'
        There are five lock types. Each has aliases that read differently but
        behave identically — use whichever is clearest, though the canonical name
        (the first in each row) is the one this documentation uses. See
        [Choosing a lock type](/docs/choosing-a-lock-type) for when to reach for
        each.

        | Canonical | Aliases | Holds the lock |
        |-----------|---------|----------------|
        | `:until_executed` | `:until_completed`, `:until_performed`, `:until_processed`, `:until_successfully_completed` | From enqueue until the job finishes |
        | `:until_executing` | `:while_enqueued` | From enqueue until the job starts running |
        | `:until_expired` | — | From enqueue until the TTL expires |
        | `:while_executing` | `:around_perform`, `:while_busy`, `:while_working` | Only while the job runs (prevents concurrent execution) |
        | `:while_executing_reject` | — | Like `:while_executing`, but forces `on_conflict: :reject` on the server |
        | `:until_and_while_executing` | — | From enqueue until start, then again for the duration of the run |
      MD
    end
  end

  def conflict_strategies
    DocsUI::Section("on_conflict strategies", description: "What happens to a job that loses the race for a lock.") do
      md <<~'MD'
        When a duplicate can't acquire the lock, the conflict strategy decides its
        fate. Pass one symbol, or a `{ client:, server: }` hash to use different
        strategies on the enqueue side and the execution side.

        | Strategy | Behavior |
        |----------|----------|
        | `:log` | Log the conflict and discard the duplicate. This is the effective default. |
        | `:raise` | Raise so Sidekiq retries the job later. |
        | `:reject` | Push the duplicate to the Dead set. |
        | `:replace` | Delete the existing job and lock, then enqueue the new one. |
        | `:reschedule` | Re-enqueue the duplicate to run later. |
      MD

      DocsUI::Callout(:tip) do
        plain "A while_executing conflict happens during execution, so its on_conflict is a server-side strategy. Split the two sides when the client and server should behave differently, e.g. on_conflict: { client: :log, server: :reschedule }."
      end

      md <<~'MD'
        See [Conflict resolution](/docs/conflict-resolution) for worked examples of
        each strategy.
      MD
    end
  end

  def everything_together
    DocsUI::Section("A worker using many options at once") do
      md <<~'MD'
        Nothing about these options is mutually exclusive. A single worker can pin
        the lock type, cap the lock's lifetime, filter which arguments matter, and
        split its conflict behavior across client and server:
      MD

      DocsUI::Code(<<~RUBY)
        class GenerateReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_and_while_executing,
                          lock_ttl: 3_600,
                          lock_args_method: :unique_args,
                          unique_across_queues: true,
                          lock_info: true,
                          on_conflict: { client: :log, server: :reschedule }

          # Only the account_id decides uniqueness; the requested_at
          # timestamp is transient and must be ignored.
          def self.unique_args(args)
            [args.first]
          end

          def perform(account_id, requested_at)
            # One report per account_id: unique in the queue, and serialized
            # so two never render concurrently.
          end
        end
      RUBY

      md <<~'MD'
        Here the lock is held from enqueue through the end of the run, capped at one
        hour. A duplicate enqueue is logged and dropped immediately — locks are
        non-blocking, so nothing waits — while a duplicate that reaches the server is
        rescheduled. Because `lock_args_method` keys only on `account_id`, two calls
        with different `requested_at` values are still the same job.
      MD
    end
  end
end

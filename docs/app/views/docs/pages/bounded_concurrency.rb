# frozen_string_literal: true

class Views::Docs::Pages::BoundedConcurrency < DocsUI::Page
  title "Bounded concurrency"
  eyebrow "Use cases"

  def lead = "Let up to N jobs for the same arguments run at once — no more — so you can pace work against a rate-limited resource."

  def content
    the_problem
    the_worker
    how_lock_limit_works
    tuning_the_wait
  end

  private

  def the_problem
    DocsUI::Section("The problem", description: "You want concurrency, but capped.") do
      md <<~'MD'
        Serializing to one at a time is often too strict. A vendor's export API
        might allow **three** concurrent requests per account before it starts
        returning `429 Too Many Requests`. You want to use all three — running one
        at a time would waste the headroom — but never a fourth.

        That's *bounded* concurrency: not "only one," but "at most N." Set
        `lock_limit: N` and up to N jobs for the same arguments may hold the lock
        simultaneously; the N+1th is treated as a conflict.
      MD
    end
  end

  def the_worker
    DocsUI::Section("A worker capped at three", description: "while_executing with lock_limit: 3.") do
      md <<~'MD'
        Here at most three `ExportToVendorJob` runs for the same `account_id` may
        execute at once. A fourth waits up to five seconds for a slot; if none
        opens, it is rescheduled to run later instead of being dropped.
      MD

      DocsUI::Code(<<~RUBY)
        class ExportToVendorJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing,
                          lock_limit: 3,
                          lock_timeout: 5,
                          on_conflict: :reschedule

          def perform(account_id, report_id)
            report = Report.find(report_id)
            VendorClient.new(account_id).upload(report.to_csv)
          end
        end
      RUBY

      md <<~'MD'
        `:while_executing` locks just before `perform` and releases just after, so
        the cap governs **concurrent execution** — exactly what a rate-limited API
        cares about. It does not stop duplicates from piling up in the queue; it
        controls how many run at the same time. For the details of that lock type
        see [Choosing a lock type](/docs/choosing-a-lock-type).
      MD
    end
  end

  def how_lock_limit_works
    DocsUI::Section("How lock_limit works") do
      md <<~'MD'
        `lock_limit` is the number of jobs allowed to hold the same lock at once.
        It defaults to `1` — plain uniqueness, one holder. Raise it to N and the
        Nth holder still acquires; the (N+1)th is a conflict and runs your
        `on_conflict` strategy.
      MD

      DocsUI::PropTable([
        [ "lock_limit", "Integer", "1", "Maximum concurrent holders of the same digest" ],
        [ "lock_timeout", "Integer (seconds)", "0", "How long the N+1th job waits for a slot before conflicting" ],
        [ "on_conflict", "Symbol", "nil", "What to do with a job that can't get a slot in time" ]
      ])

      DocsUI::Callout(:note) do
        plain "The limit applies per digest — that is, per set of unique arguments. With lock_limit: 3, three ExportToVendorJob runs for account 1 and three for account 2 can all run at once (six total); it's the fourth for the same account that's capped."
      end
    end
  end

  def tuning_the_wait
    DocsUI::Section("Make extra jobs wait, then decide") do
      md <<~'MD'
        `lock_limit` alone rejects the surplus job the instant every slot is taken.
        Pair it with `lock_timeout` so the extra job **blocks** for a while first —
        a slot may free up as a running job finishes, and then the waiter simply
        proceeds. Only if the timeout elapses does the `on_conflict` strategy fire.

        - `lock_timeout: 5` — wait up to five seconds for a free slot.
        - `on_conflict: :reschedule` — if none opens, re-enqueue to try later
          (instead of the default of logging and discarding).

        The interplay of these two is the whole story of pacing work; see
        [TTL and timeouts](/docs/ttl-and-timeouts) for exactly what each one bounds,
        and [Conflict resolution](/docs/conflict-resolution) for the other things a
        blocked job can do.
      MD

      md <<~'MD'
        ### Related

        - **[Serialize per resource](/docs/serialize-per-resource)** — the
          `lock_limit: 1` case: strictly one job at a time per resource.
        - **[TTL and timeouts](/docs/ttl-and-timeouts)** — how the waiting window
          and the lock's lifetime differ.
      MD
    end
  end
end

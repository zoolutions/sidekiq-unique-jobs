# frozen_string_literal: true

class Views::Docs::Pages::BoundedConcurrency < DocsUI::Page
  title "Bounded concurrency"
  eyebrow "Use cases"

  def lead = "Let up to N jobs for the same arguments run at once — no more — so you can pace work against a rate-limited resource."

  def content
    the_problem
    the_worker
    how_lock_limit_works
    handling_overflow
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
        execute at once. A fourth makes one attempt, finds no free slot, and is
        rescheduled to run later instead of being dropped.
      MD

      DocsUI::Code(<<~RUBY)
        class ExportToVendorJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing,
                          lock_limit: 3,
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
        [ "on_conflict", "Symbol", "nil", "What to do with the (N+1)th job when every slot is taken" ]
      ])

      DocsUI::Callout(:note) do
        plain "The limit applies per digest — that is, per set of unique arguments. With lock_limit: 3, three ExportToVendorJob runs for account 1 and three for account 2 can all run at once (six total); it's the fourth for the same account that's capped."
      end
    end
  end

  def handling_overflow
    DocsUI::Section("What happens to the overflow job") do
      md <<~'MD'
        Locks in v9 are **non-blocking**: the (N+1)th job makes a single attempt to
        acquire a slot, and if every slot is taken it does **not** wait — the
        `on_conflict` strategy fires immediately. Choose that strategy to decide
        where the surplus job goes.

        - `on_conflict: :reschedule` — re-enqueue the job to try again later (about
          five seconds out by default), which is what you usually want for pacing.
        - Leaving `on_conflict` unset means the surplus job is **silently
          discarded** — nothing is logged. Set `on_conflict: :log` if you want the
          conflict recorded.

        See [Conflict resolution](/docs/conflict-resolution) for every strategy and
        exactly what each one does with a job that can't get a slot.
      MD

      DocsUI::Callout(:note) do
        plain "lock_timeout does not make a job wait for a slot in v9 — acquisition is a single non-blocking attempt. Overflow jobs retry later only because on_conflict: :reschedule re-enqueues them, not because they blocked."
      end

      md <<~'MD'
        ### Related

        - **[Serialize per resource](/docs/serialize-per-resource)** — the
          `lock_limit: 1` case: strictly one job at a time per resource.
        - **[Conflict resolution](/docs/conflict-resolution)** — every strategy for
          the overflow job.
      MD
    end
  end
end

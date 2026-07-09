# frozen_string_literal: true

class Views::Docs::Pages::EnqueueOnceRunSerialized < DocsUI::Page
  title "Enqueue once, run serialized"
  eyebrow "Use cases"

  def lead = "Guarantee both at once — no duplicate sits in the queue, and two copies never run at the same time for the same arguments."

  def content
    the_scenario
    the_worker
    the_lifecycle
    tuning_conflicts
    single_phase_versions
  end

  private

  def the_scenario
    DocsUI::Section("The scenario") do
      md <<~'MD'
        Sometimes one guarantee isn't enough. Debouncing enqueues keeps the queue
        clean, but says nothing once a job is running — a fresh copy can slip in
        the moment execution begins. Serializing execution stops overlap, but does
        nothing to keep duplicates out of the queue while the first copy waits.

        A report rebuild wants **both**. If `RebuildReportJob.perform_async(42)` is
        already queued, a second request for report `42` should be dropped — one
        pending rebuild is enough. And once a rebuild is actually running, no other
        rebuild for report `42` should run alongside it — they'd race on the same
        rows. That is exactly what `:until_and_while_executing` provides: it is the
        **full-lifecycle** lock, and the most protective of the five.
      MD
    end
  end

  def the_worker
    DocsUI::Section("A complete worker") do
      md <<~'MD'
        One lock type, one argument that identifies the resource. Uniqueness is
        keyed on the worker class, the queue, and the arguments — so report `42`
        and report `43` are independent, but a second `perform_async(42)` while the
        first is still in flight is a duplicate.
      MD

      DocsUI::Code(<<~RUBY)
        class RebuildReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_and_while_executing,
                          on_conflict: { client: :log, server: :reschedule }

          def perform(report_id)
            report = Report.find(report_id)
            report.recompute_rollups!
            report.regenerate_pdf!
          end
        end
      RUBY

      md <<~'MD'
        `RebuildReportJob.perform_async(42)` acquires the lock at enqueue. A second
        `perform_async(42)` before the first runs finds the queue lock held and is
        logged and discarded. When the first job reaches the worker, it re-acquires
        the lock for execution — so if two rebuilds ever do run in overlapping
        windows, the later one is rescheduled to run after the first releases.
      MD
    end
  end

  def the_lifecycle
    DocsUI::Section("The full lifecycle", description: "Both phases of a single lock, in order.") do
      md <<~'MD'
        `:until_and_while_executing` is two locks in one, chained across the job's
        life. Follow a single job from `perform_async` to done:

        1. **Locked at enqueue (client).** The queue lock is acquired the moment
           the job is pushed. While it's held, another `perform_async` with the
           same arguments is a conflict — with `client: :log`, it's logged and
           discarded, so only one copy ever sits in the queue.
        2. **Released just before perform (server).** When the job is picked up and
           is about to run, the queue lock is released. The queue is now free to
           accept the *next* rebuild for this report — you're no longer debouncing,
           you're serializing.
        3. **Re-locked for execution (server).** Immediately before `perform` runs,
           an execution lock is acquired. If another copy of this job is already
           executing, the new one can't get it — with `server: :reschedule`, it's
           re-enqueued to try again later, guaranteeing the two never overlap.
        4. **Released after perform (server).** When `perform` returns, the
           execution lock is released and the next serialized rebuild may run.

        The handoff between step 2 and step 3 is what makes this lock distinct: the
        queue lock ends exactly where the execution lock begins, so there is no
        window where the same arguments are either duplicated in the queue or
        running twice.
      MD

      DocsUI::Callout(:note) do
        plain "Because the queue lock is released before perform starts, this lock does not keep a duplicate out of the queue while an earlier copy is executing — instead, that duplicate is caught by the execution lock and serialized."
      end
    end
  end

  def tuning_conflicts
    DocsUI::Section("Choosing conflict strategies for each phase") do
      md <<~'MD'
        Because there are two phases, `on_conflict` can carry two strategies — one
        for the queue lock (`client`) and one for the execution lock (`server`):
      MD

      DocsUI::Code(<<~RUBY)
        sidekiq_options lock: :until_and_while_executing,
                        on_conflict: { client: :log, server: :reschedule }
      RUBY

      md <<~'MD'
        - **`client:`** decides what happens to a duplicate *enqueue*. `:log`
          discards it quietly; `:reject` sends it to the Dead set; `:replace`
          deletes the existing lock and enqueues the new job.
        - **`server:`** decides what happens when a copy tries to *run* while
          another is executing. `:reschedule` re-enqueues it to run later (the
          natural choice here — you want the work to happen, just not concurrently);
          `:raise` lets Sidekiq retry it; `:log` drops it.

        A single symbol applies to both phases, e.g. `on_conflict: :reschedule`.
        The default is effectively `:log` for both. See
        [Conflict resolution](/docs/conflict-resolution) for the full strategy list.
      MD

      DocsUI::Callout(:tip) do
        plain "Reach for :reschedule on the server side when the work must eventually run but never in parallel. Reach for :log on the client side when a second pending copy is simply redundant."
      end
    end
  end

  def single_phase_versions
    DocsUI::Section("When you only need one guarantee") do
      md <<~'MD'
        `:until_and_while_executing` is the combination. If you only need one half
        of it, pick the single-phase lock instead — it's simpler and holds a lock
        for less time:

        - **[Serialize per resource](/docs/serialize-per-resource)** uses
          `:while_executing` — it prevents concurrent *execution* only, and does
          nothing to keep duplicates out of the queue.
        - **[Debounce duplicate enqueues](/docs/debounce-duplicate-enqueues)** uses
          `:until_executing` — it collapses duplicate *enqueues*, then releases the
          lock as soon as the job starts running, allowing a fresh copy to queue.

        Choose the combined lock only when you genuinely need both at once. If
        you're unsure which fits, start from
        [Choosing a lock type](/docs/choosing-a-lock-type).
      MD
    end
  end
end

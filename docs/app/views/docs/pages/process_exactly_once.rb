# frozen_string_literal: true

class Views::Docs::Pages::ProcessExactlyOnce < DocsUI::Page
  title "Process exactly once"
  eyebrow "Use cases"

  def lead = "A payment or webhook event must be handled once for the whole push-to-done lifecycle; a retry of the same event while the first is still working is a duplicate."

  def content
    the_scenario
    the_worker
    walkthrough
    conflict_choice
    what_exactly_once_means
    where_to_go
  end

  private

  def the_scenario
    DocsUI::Section("The scenario") do
      md <<~'MD'
        A provider sends you a webhook: *payment `evt_123` settled*. You enqueue a
        job to record it. Before that job finishes, the provider — nervous about
        your `200` — sends the exact same event again. Now you have two jobs for
        one settlement, racing to write the same row.

        You want the event processed **once**: from the moment it's enqueued until
        the work is actually done, no second copy with the same `event_id` gets in.
        The moment the job completes, the lock lifts and a *later* delivery of the
        same event is free to run again.

        That's exactly what `:until_executed` does — it holds the lock across the
        whole lifecycle, releasing only **after** `perform` returns.
      MD
    end
  end

  def the_worker
    DocsUI::Section("A complete worker", description: "Lock on the event id, from enqueue until the work is done.") do
      DocsUI::Code(<<~RUBY)
        class SettlePaymentJob
          include Sidekiq::Job

          sidekiq_options queue: :payments,
                          lock: :until_executed,
                          lock_args_method: :unique_args

          # Only the event id decides uniqueness — the payload can differ between
          # deliveries, but the same event is the same job.
          def self.unique_args(args)
            [args.first]
          end

          def perform(event_id, _payload = {})
            payment = Payment.find_by!(external_event_id: event_id)
            payment.settle!
          end
        end
      RUBY

      md <<~'MD'
        `SettlePaymentJob.perform_async("evt_123")` acquires the lock at enqueue.
        A second `perform_async("evt_123")` — a retry delivery — finds the lock
        held and is prevented while the first job is still in flight. A different
        event, `perform_async("evt_456")`, is independent and runs freely.

        The `lock_args_method` keeps a jittery payload from breaking uniqueness:
        only the first argument (the event id) feeds the digest, so two deliveries
        of the same event collide even if their payload hashes differ. See
        [Custom uniqueness arguments](/docs/custom-uniqueness-arguments).
      MD
    end
  end

  def walkthrough
    DocsUI::Section("How the lock moves") do
      md <<~'MD'
        `:until_executed` is a client-side lock that survives into execution:

        1. **Enqueue (client).** `perform_async` acquires the lock keyed on the
           worker class, queue, and `unique_args`. The job goes onto the queue.
        2. **Duplicate enqueue.** A second push with the same event id finds the
           lock held and is stopped by the conflict strategy — it never reaches
           the queue.
        3. **Execution (server).** A worker picks the job up and runs `perform`.
           The lock stays held for the entire duration of the work.
        4. **Release (server).** Only **after** `perform` returns successfully is
           the lock released. From that instant, the same event may be enqueued
           and run again.
      MD

      DocsUI::Callout(:tip) do
        plain "Because the lock is held across execution, a duplicate delivery that arrives mid-work is dropped, not queued behind the first job. If you instead want to release the lock the moment work starts — so a fresh copy can queue while the current one runs — use "
        a(href: "/docs/debounce-duplicate-enqueues") { "until_executing" }
        plain " instead."
      end
    end
  end

  def conflict_choice
    DocsUI::Section("What happens to the duplicate") do
      md <<~'MD'
        By default a blocked duplicate is handled by the `:log` strategy — it's
        logged and **discarded**. For a lot of webhook and payment work that's
        exactly right: the retry delivery is redundant, so dropping it silently is
        the goal.

        Sometimes you'd rather not lose the duplicate quietly. For webhooks where
        an unhandled event should be visible and manually inspectable, send it to
        the Dead set with `:reject`:
      MD

      DocsUI::Code(<<~RUBY)
        class SettlePaymentJob
          include Sidekiq::Job

          sidekiq_options queue: :payments,
                          lock: :until_executed,
                          on_conflict: :reject,
                          lock_args_method: :unique_args

          def self.unique_args(args)
            [args.first]
          end

          def perform(event_id, _payload = {})
            Payment.find_by!(external_event_id: event_id).settle!
          end
        end
      RUBY

      md <<~'MD'
        The full menu — `:log`, `:raise`, `:reject`, `:replace`, `:reschedule`,
        and splitting client vs. server behavior — is on
        [Conflict resolution](/docs/conflict-resolution).
      MD
    end
  end

  def what_exactly_once_means
    DocsUI::Section("What \"exactly once\" means here") do
      DocsUI::Callout(:warning) do
        plain "This is de-duplication while a lock is held, not distributed-systems exactly-once delivery. The lock guarantees no duplicate runs while the first job holds it. Once that job completes and the lock lifts, a later delivery of the same event will run again — and a process that crashes mid-work may leave a lock to be cleaned up by the reaper. Make perform idempotent so a legitimate re-run is harmless."
      end

      md <<~'MD'
        In practice: keep `perform` safe to run twice. Look the event up, and make
        the write a no-op if it already happened (`settle!` on an already-settled
        payment should do nothing). The lock removes the *concurrent* duplicate;
        idempotency covers the *eventual* one.
      MD
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[Conflict resolution](/docs/conflict-resolution)** — choose what
          happens to a blocked duplicate: drop, retry, reject, replace, reschedule.
        - **[Custom uniqueness arguments](/docs/custom-uniqueness-arguments)** —
          pick exactly which arguments decide that two jobs are the same.
        - **[Choosing a lock type](/docs/choosing-a-lock-type)** — the decision
          table from "I want to prevent X" to the lock that does it.
      MD
    end
  end
end

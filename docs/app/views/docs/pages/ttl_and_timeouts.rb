# frozen_string_literal: true

class Views::Docs::Pages::TtlAndTimeouts < DocsUI::Page
  title "TTL and timeouts"
  eyebrow "Concepts"

  def lead = "lock_ttl and lock_timeout sound alike and are constantly confused — one bounds how long the lock lives, the other bounds how long you wait to get it."

  def content
    the_confusion
    lock_ttl
    lock_timeout
    they_are_independent
  end

  private

  def the_confusion
    DocsUI::Section("Two settings, one letter apart") do
      md <<~'MD'
        `lock_ttl` and `lock_timeout` are the two most commonly mixed-up options
        in the gem. They read alike, they both take a number of seconds, and
        they both sound like "how long". But they answer completely different
        questions:

        - **`lock_ttl`** — how long the **lock lives** in Redis before it expires
          on its own.
        - **`lock_timeout`** — how long a client will **wait to acquire** a lock
          that someone else is already holding, before giving up.

        One is about the lock's *lifetime*. The other is about your *patience*.
        They do not interact, and setting one tells you nothing about the other.
      MD

      DocsUI::Callout(:tip) do
        plain "The mental model: ttl bounds the lock's lifetime; timeout bounds how long you wait to get it."
      end
    end
  end

  def lock_ttl
    DocsUI::Section("lock_ttl — how long the lock lives", description: "Expiry is measured from when the lock is created, not from when the job finishes.") do
      md <<~'MD'
        `lock_ttl` is a number of seconds after which Redis expires the lock
        automatically. The clock starts the moment the lock is **created** — for
        a client lock that is at **enqueue time**, not when the job runs or
        completes. A `lock_ttl` of `86_400` means "this lock is gone 24 hours
        after it was placed", full stop.

        This is exactly what you want for time-boxed uniqueness. The classic case
        is a job that should run at most once per period: pair `:until_expired`
        with a TTL equal to the window.
      MD

      DocsUI::Code(<<~RUBY)
        class DailyDigestJob
          include Sidekiq::Job

          # One digest per user per day. The lock is created at enqueue and
          # expires 24 hours later — regardless of when (or whether) the job runs.
          sidekiq_options lock: :until_expired, lock_ttl: 86_400

          def perform(user_id)
            DigestMailer.daily(user_id).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        Because the TTL is anchored to creation, a slow or long-running job does
        **not** extend the lock. If `DailyDigestJob` sits in the queue for two
        hours and then takes ten minutes to run, the lock still expires 24 hours
        after it was enqueued — the runtime is irrelevant.

        A few consequences worth internalizing:

        - `:until_expired` releases **only** by TTL. Completing the job does not
          unlock it, and its [after_unlock](/docs/one-per-period) callback never
          fires — there is no "unlock event", just an expiry.
        - For other lock types, `lock_ttl` acts as a **safety net**: if a process
          crashes and the lock is never released cleanly, the TTL guarantees the
          lock eventually goes away on its own.
        - Leave `lock_ttl` unset (`nil`, the default) and the lock has **no
          expiry** — it lives until the job's lifecycle releases it, backed by the
          [reaper](/docs/one-per-period) for orphan cleanup.
      MD

      DocsUI::Callout(:warning) do
        plain "Because expiry is measured from creation, do not size lock_ttl to a job's runtime. Size it to the window you want uniqueness to last."
      end
    end
  end

  def lock_timeout
    DocsUI::Section("lock_timeout — how long you wait to acquire", description: "0 (the default) means fail fast: don't wait, act on the conflict immediately.") do
      md <<~'MD'
        `lock_timeout` controls what happens when the lock you want is **already
        held** by another copy of the job. It is the number of seconds the client
        will **block, waiting** for that lock to free up before it gives up and
        hands the duplicate to your [conflict strategy](/docs/conflict-resolution).

        The default is `0`, which means **do not wait at all**. If the lock is
        taken, the client fails immediately and the conflict strategy runs right
        away. This "fail fast" behavior is what you want for debouncing — a
        duplicate enqueue should be dropped now, not queued up behind the
        original.
      MD

      DocsUI::Code(<<~RUBY)
        class ProcessUploadJob
          include Sidekiq::Job

          # Serialize per-account processing. If one is already running,
          # wait up to 5 seconds for it to finish before deciding what to do.
          sidekiq_options lock: :while_executing,
                          lock_timeout: 5,
                          on_conflict: :reschedule

          def perform(account_id)
            # Only one ProcessUploadJob per account_id runs at a time.
          end
        end
      RUBY

      md <<~'MD'
        With `lock_timeout: 5` above, a second job for the same account will
        block for up to five seconds hoping the running job finishes. If it does,
        the waiting job acquires the lock and proceeds. If five seconds elapse and
        the lock is still held, the `:reschedule` strategy takes over and the
        duplicate is re-enqueued to try again later.

        Contrast that with the fail-fast default:
      MD

      DocsUI::Code(<<~RUBY)
        class SendWelcomeEmailJob
          include Sidekiq::Job

          # lock_timeout defaults to 0: if a duplicate is already locked,
          # don't wait — log it and discard immediately.
          sidekiq_options lock: :until_executed, on_conflict: :log

          def perform(user_id)
            WelcomeMailer.greet(user_id).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        Here `lock_timeout` is `0`, so a second `perform_async` for the same user
        does not wait — it immediately triggers `:log` and the duplicate is
        discarded. That is precisely the behavior you want when the goal is to
        collapse duplicate enqueues.
      MD
    end
  end

  def they_are_independent
    DocsUI::Section("They are independent") do
      md <<~'MD'
        `lock_ttl` and `lock_timeout` do not affect each other. You can set
        either, both, or neither, and each keeps its own meaning:

        | Setting | Answers | Default | Measured from |
        |---------|---------|---------|---------------|
        | `lock_ttl` | How long does the lock live? | `nil` (no expiry) | Lock **creation** (enqueue for client locks) |
        | `lock_timeout` | How long do I wait to acquire it? | `0` (don't wait) | The acquisition attempt |

        A job can have a long-lived lock that you refuse to wait for
        (`lock_ttl: 86_400, lock_timeout: 0`), a short lock you'll wait patiently
        for (`lock_ttl: 60, lock_timeout: 30`), or any other combination. Pick
        each value from the question it answers, not from the other.
      MD

      DocsUI::Code(<<~RUBY)
        class ReportBuilderJob
          include Sidekiq::Job

          # Lock survives at most 10 minutes as a crash safety net (ttl),
          # and callers wait up to 30 seconds to acquire it (timeout).
          sidekiq_options lock: :until_and_while_executing,
                          lock_ttl: 600,
                          lock_timeout: 30,
                          on_conflict: :reschedule

          def perform(report_id)
            # Unique in the queue AND serialized during execution.
          end
        end
      RUBY

      md <<~'MD'
        See these in action in the use-case pages:

        - **[One per period](/docs/one-per-period)** — `:until_expired` with a
          `lock_ttl` sized to the window.
        - **[Bounded concurrency](/docs/bounded-concurrency)** — `lock_timeout`
          controlling how long callers wait for a contended slot.
      MD
    end
  end
end

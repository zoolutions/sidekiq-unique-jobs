# frozen_string_literal: true

class Views::Docs::Pages::TtlAndTimeouts < DocsUI::Page
  title "TTL and timeouts"
  eyebrow "Concepts"

  def lead = "lock_ttl and lock_timeout sound alike and are constantly confused — one bounds how long the lock lives; the other historically bounded how long you wait to get it, but is inert under v9's non-blocking model."

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
          on its own. This is real and important.
        - **`lock_timeout`** — historically, how long a client would **wait to
          acquire** a contended lock before giving up. In **v9 this no longer
          waits**: acquisition is a single non-blocking attempt, so
          `lock_timeout` does not delay anything.

        One is about the lock's *lifetime* — and it works. The other used to be
        about your *patience* — but v9 removed the waiting entirely.
      MD

      DocsUI::Callout(:tip) do
        plain "The mental model: lock_ttl bounds the lock's real lifetime. lock_timeout historically bounded the acquisition wait, but v9 acquisition is non-blocking, so lock_timeout no longer causes waiting."
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
          [reaper](/docs/orphaned-locks-and-recovery) for orphan cleanup.
      MD

      DocsUI::Callout(:warning) do
        plain "Because expiry is measured from creation, do not size lock_ttl to a job's runtime. Size it to the window you want uniqueness to last."
      end
    end
  end

  def lock_timeout
    DocsUI::Section("lock_timeout — historically the acquisition wait, inert in v9", description: "v9 acquisition is non-blocking: lock_timeout no longer makes anything wait.") do
      md <<~'MD'
        `lock_timeout` was, in earlier versions, the number of seconds a client
        would **block, waiting** for a contended lock to free up before giving up
        and handing the duplicate to your
        [conflict strategy](/docs/conflict-resolution).

        **In v9 this waiting no longer happens.** Lock acquisition is a single,
        non-blocking attempt: the job either gets the lock or it does not, and on
        failure the conflict strategy fires **immediately**. `lock_timeout` is
        still parsed and stored in the lock's metadata, but it does **not** cause
        the client — or a `:while_executing` server lock — to wait for a held
        lock. There is no "wait up to N seconds and then acquire it" behavior in
        v9. The default remains `0`.
      MD

      DocsUI::Callout(:warning) do
        plain "Do not size lock_timeout expecting a job to wait. In v9 acquisition never blocks: a contended lock fails on its one attempt and the conflict strategy runs at once."
      end

      md <<~'MD'
        Because acquisition never blocks, the way to handle contention is the
        **conflict strategy**, not a timeout. If you want a duplicate to try again
        later, use `:reschedule` — it re-enqueues the job to run shortly after
        (about five seconds later by default):
      MD

      DocsUI::Code(<<~RUBY)
        class ProcessUploadJob
          include Sidekiq::Job

          # Serialize per-account processing. If one is already running, the
          # duplicate fails its single acquisition attempt immediately and
          # :reschedule re-enqueues it to try again a few seconds later.
          sidekiq_options lock: :while_executing,
                          on_conflict: :reschedule

          def perform(account_id)
            # Only one ProcessUploadJob per account_id runs at a time.
          end
        end
      RUBY

      md <<~'MD'
        With `:reschedule` above, a second job for the same account does **not**
        wait for the running job. It fails to acquire the lock right away, and the
        `:reschedule` strategy re-enqueues it to run again later — repeating until
        the account is free.

        Contrast that with the default fail-and-discard behavior:
      MD

      DocsUI::Code(<<~RUBY)
        class SendWelcomeEmailJob
          include Sidekiq::Job

          # No on_conflict set: if a duplicate is already locked, it is
          # silently discarded. Add on_conflict: :log to have it logged.
          sidekiq_options lock: :until_executed

          def perform(user_id)
            WelcomeMailer.greet(user_id).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        Here a second `perform_async` for the same user fails acquisition
        immediately and — with no `on_conflict` configured — the duplicate is
        **silently dropped** (the default strategy is a no-op; nothing is logged).
        Add `on_conflict: :log` if you want the discard recorded. Either way, no
        waiting happens: that is exactly what you want when the goal is to collapse
        duplicate enqueues.
      MD
    end
  end

  def they_are_independent
    DocsUI::Section("They are independent") do
      md <<~'MD'
        `lock_ttl` and `lock_timeout` do not affect each other. They keep their
        own meanings — but only `lock_ttl` has runtime effect in v9:

        | Setting | Answers | Default | Effect in v9 |
        |---------|---------|---------|--------------|
        | `lock_ttl` | How long does the lock live? | `nil` (no expiry) | **Real** — Redis expires the lock this long after **creation** (enqueue for client locks) |
        | `lock_timeout` | How long do I wait to acquire it? | `0` | **Inert** — acquisition is non-blocking; it never waits |

        The takeaway: reach for `lock_ttl` to bound how long a lock lives, and
        rely on the **conflict strategy** — not `lock_timeout` — to decide what
        happens when a lock is contended.
      MD

      DocsUI::Code(<<~RUBY)
        class ReportBuilderJob
          include Sidekiq::Job

          # Lock survives at most 10 minutes as a crash safety net (ttl).
          # Contention is handled by :reschedule, not by waiting — a duplicate
          # fails acquisition immediately and is re-enqueued to try again.
          sidekiq_options lock: :until_and_while_executing,
                          lock_ttl: 600,
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
        - **[Bounded concurrency](/docs/bounded-concurrency)** — using a lock and
          a conflict strategy (not a waiting timeout) to serialize contended work.
      MD
    end
  end
end

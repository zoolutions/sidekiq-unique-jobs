# frozen_string_literal: true

class Views::Docs::Pages::SerializePerResource < DocsUI::Page
  title "Serialize per resource"
  eyebrow "Use cases"

  def lead = "Run at most one job per resource at a time — never two balance syncs for the same account concurrently — while different accounts still run in parallel."

  def content
    the_scenario
    the_worker
    walkthrough
    per_args_uniqueness
    the_pitfall
    where_to_go
  end

  private

  def the_scenario
    DocsUI::Section("The scenario") do
      md <<~'MD'
        You sync a bank account's balance from an external provider. Running two
        syncs for the **same account** at the same time corrupts the balance —
        they race on the same rows. But two syncs for **different** accounts are
        completely independent and should run in parallel for throughput.

        You don't care if a duplicate sync for account `42` gets *enqueued* while
        another is running — you only care that they never *execute* at the same
        time. That's exactly what `:while_executing` gives you: a lock taken on
        the server, keyed on the arguments, held only for the duration of
        `perform`.
      MD
    end
  end

  def the_worker
    DocsUI::Section("The worker") do
      md <<~'MD'
        `:while_executing` locks just before `perform` runs and releases just
        after. Because the lock is keyed on the arguments, `account_id` becomes
        the thing that's serialized:
      MD

      DocsUI::Code(<<~RUBY)
        class SyncAccountBalanceJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing,
                          lock_timeout: 10,
                          on_conflict: :reschedule

          def perform(account_id)
            account = Account.find(account_id)
            account.sync_balance_from_provider!
          end
        end
      RUBY

      md <<~'MD'
        - `lock: :while_executing` — the lock is taken on the **server**, right
          before `perform`, and released right after. It has no effect at enqueue
          time.
        - `lock_timeout: 10` — when a copy for the same account is already running,
          wait up to 10 seconds for it to finish before giving up.
        - `on_conflict: :reschedule` — if the wait runs out, re-enqueue this copy
          to try again later instead of dropping it. Because `:while_executing`
          conflicts happen during execution, this is a **server** conflict
          strategy.
      MD
    end
  end

  def walkthrough
    DocsUI::Section("What happens on a duplicate", description: "Two syncs for the same account, arriving close together.") do
      md <<~'MD'
        Say two `SyncAccountBalanceJob` copies for account `42` land on your
        workers at nearly the same time:

        1. **Copy A** reaches `perform`. `:while_executing` acquires the lock keyed
           on `[42]` and starts syncing.
        2. **Copy B** reaches `perform` a moment later and tries to acquire the
           same lock. It's held, so B **blocks**, waiting up to `lock_timeout`
           (10s).
        3. If A finishes and releases the lock within 10 seconds, B acquires it and
           runs — the two syncs happen back-to-back, never concurrently.
        4. If A is still running when B's 10 seconds elapse, B's acquisition fails
           and `on_conflict: :reschedule` re-enqueues B to try again later.

        Meanwhile a `SyncAccountBalanceJob` for account `43` has a **different**
        digest, so it never contends with either — it runs in parallel.
      MD
    end
  end

  def per_args_uniqueness
    DocsUI::Section("Why it serializes per resource") do
      md <<~'MD'
        Uniqueness is computed from the worker class, the queue, and **the
        arguments**. Two calls with the same `account_id` produce the same digest
        and therefore compete for one lock; two calls with different `account_id`s
        produce different digests and never see each other. The `account_id`
        argument *is* the serialization key — no extra configuration needed.

        If your `perform` takes arguments that shouldn't affect uniqueness (a
        timestamp, a request id), narrow the digest to just the resource id with
        `lock_args_method`:
      MD

      DocsUI::Code(<<~RUBY)
        class SyncAccountBalanceJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing,
                          lock_timeout: 10,
                          on_conflict: :reschedule,
                          lock_args_method: :unique_args

          def self.unique_args(args)
            [args.first] # serialize on account_id only, ignore the rest
          end

          def perform(account_id, requested_at)
            account = Account.find(account_id)
            account.sync_balance_from_provider!(as_of: requested_at)
          end
        end
      RUBY
    end
  end

  def the_pitfall
    DocsUI::Section("The pitfall: it does not stop duplicate enqueues") do
      md <<~'MD'
        `:while_executing` locks on the **server**, only around execution. It does
        **not** run at enqueue time, so it will not stop a duplicate copy from
        being *pushed onto the queue*. Fire `perform_async(42)` ten times and all
        ten land in the queue — `:while_executing` only guarantees they don't
        *run* at the same time; they run one after another.
      MD

      DocsUI::Callout(:warning) do
        plain "If duplicate copies piling up in the queue is a problem — not just concurrent execution — you want a client-side lock too. See "
        a(href: "/docs/enqueue-once-run-serialized") { "Enqueue once, run serialized" }
        plain "."
      end
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[Enqueue once, run serialized](/docs/enqueue-once-run-serialized)** —
          when you need *both* a single queued copy *and* serialized execution,
          use `:until_and_while_executing`.
        - **[Bounded concurrency](/docs/bounded-concurrency)** — allow up to *N*
          concurrent runs of the same digest instead of exactly one, with
          `lock_limit`.
      MD
    end
  end
end

# frozen_string_literal: true

class Views::Docs::Pages::DebounceDuplicateEnqueues < DocsUI::Page
  title "Debounce duplicate enqueues"
  eyebrow "Use cases"

  def lead = "Collapse a burst of identical enqueues down to a single queued job, while still letting a fresh request in once the job starts running."

  def content
    the_scenario
    the_worker
    the_walkthrough
    tuning
    not_concurrency
  end

  private

  def the_scenario
    DocsUI::Section("The scenario") do
      md <<~'MD'
        A product changes, and something fires a "reindex this product" trigger.
        Then it fires again. And again — an admin saves the form three times, a
        webhook retries, a bulk import touches the same record twice. You want
        **one** reindex sitting in the queue, not five identical copies.

        But there's a wrinkle: reindexing takes a while, and the product might
        change *again* while a reindex is already running. Once the job has
        started, a new trigger should be allowed to enqueue a fresh reindex — the
        one in flight is working from stale data.

        That's exactly what [`:until_executing`](/docs/choosing-a-lock-type)
        gives you. The lock is held from the moment the job is enqueued and
        released the instant it starts executing — so duplicates collapse while
        the job waits in the queue, but the door reopens as soon as it runs.
      MD
    end
  end

  def the_worker
    DocsUI::Section("A complete worker", description: "One reindex per product in the queue at a time.") do
      DocsUI::Code(<<~RUBY)
        class ReindexProductJob
          include Sidekiq::Job

          sidekiq_options queue: "search", lock: :until_executing

          def perform(product_id)
            product = Product.find(product_id)
            SearchIndex.reindex(product)
          end
        end
      RUBY

      md <<~'MD'
        The digest is built from the worker class, the queue, and the arguments,
        so each `product_id` is tracked independently:
        `ReindexProductJob.perform_async(1)` and `perform_async(2)` never collide.
        A second `perform_async(1)` fired while the first is still waiting in the
        queue is the duplicate — and it's dropped.
      MD

      DocsUI::Callout(:note) do
        plain "The middleware is not loaded automatically. Wire it up once in your Sidekiq initializer — see "
        a(href: "/docs/installation") { "Installation" }
        plain "."
      end
    end
  end

  def the_walkthrough
    DocsUI::Section("What happens when a duplicate arrives") do
      md <<~'MD'
        Walk a burst of triggers through the lock's lifecycle:

        1. **First trigger enqueues.** `ReindexProductJob.perform_async(42)` is
           pushed. The client middleware acquires the `:until_executing` lock for
           the digest of `ReindexProductJob` + `search` + `[42]`. The job sits in
           the queue, locked.
        2. **Duplicates arrive while it waits.** Two more triggers fire
           `perform_async(42)` before a worker picks the job up. Each makes a
           single attempt to acquire the same lock, finds it held, and is
           **silently discarded** — by default nothing is logged; the duplicate
           is simply dropped. (Set `on_conflict: :log` if you want each dropped
           duplicate written to the log.) The queue still holds exactly one
           reindex for product 42.
        3. **A worker picks it up.** Just **before** `perform` runs, the server
           middleware releases the lock. The digest is now free.
        4. **A fresh trigger mid-run is allowed.** While `SearchIndex.reindex`
           is still churning, a new `perform_async(42)` comes in. Because the lock
           was already released in step 3, this one acquires the lock cleanly and
           enqueues a fresh reindex — which is what you want, since the product
           may have changed since the running job read it.

        The key moment is step 3: the lock unlocks **just before** the job starts,
        not after it finishes. That single choice is the entire difference between
        `:until_executing` and [`:until_executed`](/docs/choosing-a-lock-type),
        which holds the lock across the whole run.
      MD
    end
  end

  def tuning
    DocsUI::Section("Tuning knobs") do
      md <<~'MD'
        Two options adjust how the debounce behaves under contention. Neither is
        required — the worker above works as-is.
      MD

      DocsUI::PropTable([
        [ "lock_ttl", "Integer (seconds)", "nil", "A safety expiry for the lock. Measured from when the lock is created (at enqueue), not from job completion. Set this so a crash between enqueue and pickup can't wedge the digest forever." ],
        [ "on_conflict", "Symbol", "nil", "What to do with a duplicate. Unset, the duplicate is silently discarded — nothing is logged. Set :log to have each dropped duplicate logged, :reschedule to re-enqueue it to run later, or :replace to swap the queued job for the newer one." ]
      ])

      md <<~'MD'
        For example, to drop stale triggers but never let a lock outlive a lost
        job:
      MD

      DocsUI::Code(<<~RUBY)
        class ReindexProductJob
          include Sidekiq::Job

          sidekiq_options queue: "search",
                          lock: :until_executing,
                          lock_ttl: 300,
                          on_conflict: :log

          def perform(product_id)
            product = Product.find(product_id)
            SearchIndex.reindex(product)
          end
        end
      RUBY

      md <<~'MD'
        See [Conflict resolution](/docs/conflict-resolution) for every strategy.
        Note that `lock_ttl` bounds the lock's *lifetime* in Redis. Lock
        acquisition itself is non-blocking in v9 — a contended enqueue makes one
        attempt and, on failure, the conflict strategy fires immediately. A job
        never waits for a held lock to free up.
      MD
    end
  end

  def not_concurrency
    DocsUI::Section("It does not prevent concurrent execution") do
      md <<~'MD'
        This is the pitfall to internalize. `:until_executing` releases the lock
        **before** `perform` runs — so nothing stops two copies of
        `ReindexProductJob` from executing at the same time. In fact the mid-run
        enqueue in step 4 above is designed to allow exactly that.

        If your goal is that only one reindex for a given product **runs** at a
        time — never two overlapping — that's a different job. Reach for
        [Serialize per resource](/docs/serialize-per-resource), which holds the
        lock across execution instead of releasing it beforehand.
      MD

      DocsUI::Callout(:tip) do
        plain "Rule of thumb: use :until_executing to keep the queue clean, and a while-executing lock to keep execution serialized. Combine both with :until_and_while_executing when you need each — see "
        a(href: "/docs/choosing-a-lock-type") { "Choosing a lock type" }
        plain "."
      end
    end
  end
end

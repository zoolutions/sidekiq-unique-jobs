# frozen_string_literal: true

class Views::Docs::Pages::ChoosingALockType < DocsUI::Page
  title "Choosing a lock type"
  eyebrow "Concepts"

  def lead = "Start from what you want to prevent, and the right lock type falls out of a single decision table."

  def content
    decision_table
    until_executing
    until_executed
    until_expired
    while_executing
    until_and_while_executing
    aliases
    while_executing_warning
  end

  private

  def decision_table
    DocsUI::Section("Start here", description: "Match your goal to a lock type, then read the section below it.") do
      md <<~'MD'
        A lock type answers one question: **when is the lock held?** Every lock is
        acquired at either enqueue or the start of execution, and released at some
        later point. Find the row that matches what you're trying to prevent.

        | I want to…                                            | Lock type                    | Use case |
        |-------------------------------------------------------|------------------------------|----------|
        | prevent the same job sitting in the queue twice       | `:until_executing`           | [Debounce duplicate enqueues](/docs/debounce-duplicate-enqueues) |
        | prevent duplicates until the job finishes             | `:until_executed`            | [Process exactly once](/docs/process-exactly-once) |
        | allow only one per time window                        | `:until_expired` + `lock_ttl`| [One per period](/docs/one-per-period) |
        | never run two copies at the same time                 | `:while_executing`           | [Serialize per resource](/docs/serialize-per-resource) |
        | both — unique in the queue **and** serialized at run  | `:until_and_while_executing` | [Enqueue once, run serialized](/docs/enqueue-once-run-serialized) |

        Every option is set the same way — one `lock:` key in `sidekiq_options`.
        The sections below give the exact locks-at / unlocks-at behavior and the
        tradeoff for each.
      MD
    end
  end

  def until_executing
    DocsUI::Section(":until_executing", description: "Locks at enqueue, unlocks just before perform starts.") do
      md <<~'MD'
        Holds the lock from the moment the job is enqueued until just **before**
        `perform` begins. This debounces a burst of enqueues down to a single
        queued job.

        **Tradeoff:** the lock releases the instant the job starts running, so a
        fresh copy can be enqueued *while the original is executing*. If you need
        the original to keep its exclusivity through execution, reach for
        `:until_executed` instead.
      MD

      DocsUI::Code(<<~RUBY)
        class SyncContactJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executing

          def perform(contact_id)
            # Rapid re-triggers collapse into one queued job.
          end
        end
      RUBY

      md <<~'MD'
        See [Debounce duplicate enqueues](/docs/debounce-duplicate-enqueues) for a
        complete walkthrough.
      MD
    end
  end

  def until_executed
    DocsUI::Section(":until_executed", description: "Locks at enqueue, unlocks after perform completes.") do
      md <<~'MD'
        Holds the lock across the whole lifecycle — from enqueue until `perform`
        finishes. No duplicate can be enqueued *or* run while the original is
        still in flight. This is the lock most people mean when they say "unique
        job."

        **Tradeoff:** the lock lives for the full push → done span, so a slow or
        stuck job keeps the digest locked the entire time. Pair it with `lock_ttl`
        as a safety valve if a job can hang.
      MD

      DocsUI::Code(<<~RUBY)
        class ChargeCustomerJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(customer_id)
            # Exactly one charge per customer_id from enqueue to completion.
          end
        end
      RUBY

      md <<~'MD'
        See [Process exactly once](/docs/process-exactly-once) for the full pattern.
      MD
    end
  end

  def until_expired
    DocsUI::Section(":until_expired", description: "Locks at enqueue, unlocks only when the TTL expires.") do
      md <<~'MD'
        Holds the lock from enqueue until its `lock_ttl` runs out — **never** on
        completion. This gives you time-boxed uniqueness: one job per window,
        regardless of how quickly it finishes. It's the right choice for "once per
        day" style jobs.

        **Tradeoff:** because the lock releases by expiry rather than by code, the
        `after_unlock` callback never fires for this lock type. The TTL is
        measured from when the lock is *created* (at enqueue), not from when the
        job finishes — see [TTL vs timeout](/docs/lock-ttl-and-timeout).
      MD

      DocsUI::Code(<<~RUBY)
        class DailyReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_expired, lock_ttl: 86_400

          def perform(report_id)
            # Runs at most once per 24 hours per report_id.
          end
        end
      RUBY

      md <<~'MD'
        See [One per period](/docs/one-per-period) for choosing a window.
      MD

      DocsUI::Callout(:note) do
        plain "lock_ttl is required for :until_expired — without it the lock has no expiry and nothing releases it."
      end
    end
  end

  def while_executing
    DocsUI::Section(":while_executing", description: "Locks just before perform, unlocks after perform.") do
      md <<~'MD'
        Holds the lock only for the duration of execution. Duplicates queue up
        freely, but no two copies run at the same time — each waits its turn (or
        follows the conflict strategy). Use it to serialize work against a shared
        resource.

        **Tradeoff:** it does **nothing** about duplicate enqueues — the queue can
        hold many copies; they're merely run one at a time. The conflict happens on
        the server, so its `on_conflict` is a server-side strategy.
      MD

      DocsUI::Code(<<~RUBY)
        class RebuildIndexJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing

          def perform(index_name)
            # Only one rebuild of a given index runs at a time.
          end
        end
      RUBY

      md <<~'MD'
        See [Serialize per resource](/docs/serialize-per-resource) for the details.
      MD
    end
  end

  def until_and_while_executing
    DocsUI::Section(":until_and_while_executing", description: "Combines the queue lock and the execution lock.") do
      md <<~'MD'
        The combination of the two behaviors above: locks at enqueue (unique in the
        queue) **and** locks again just before `perform` (serialized during
        execution). A duplicate can't sit in the queue, and even after the queue
        lock releases at the start of a run, a second copy can't execute
        concurrently.

        **Tradeoff:** it's the strongest guarantee and the most machinery — two
        locks per job. Use it only when you genuinely need both properties; if you
        just need one, pick the simpler lock.
      MD

      DocsUI::Code(<<~RUBY)
        class DeliverInvoiceJob
          include Sidekiq::Job

          sidekiq_options lock: :until_and_while_executing

          def perform(invoice_id)
            # Unique in the queue, and never two deliveries running at once.
          end
        end
      RUBY

      md <<~'MD'
        See [Enqueue once, run serialized](/docs/enqueue-once-run-serialized) for
        when this pairing earns its cost.
      MD
    end
  end

  def aliases
    DocsUI::Section("Aliases") do
      md <<~'MD'
        Some lock types have aliases that all resolve to the same implementation.
        Use whichever reads best in your code, but prefer the canonical name in the
        first column when in doubt.

        | Canonical           | Also accepted |
        |---------------------|---------------|
        | `:until_executed`   | `:until_completed`, `:until_performed`, `:until_processed`, `:until_successfully_completed` |
        | `:until_executing`  | `:while_enqueued` |
        | `:while_executing`  | `:around_perform`, `:while_busy`, `:while_working` |

        There's also `:while_executing_reject` — a `:while_executing` lock that
        forces `on_conflict: :reject` on the server, sending conflicting jobs
        straight to the Dead set.
      MD
    end
  end

  def while_executing_warning
    DocsUI::Section("A common misunderstanding") do
      DocsUI::Callout(:warning) do
        plain ":while_executing does NOT prevent duplicate enqueues. It only stops two copies from running at the same time — the queue can still fill with duplicates, and each one runs in turn. If you also need the queue to stay unique, use :until_executed or :until_and_while_executing instead."
      end
    end
  end
end

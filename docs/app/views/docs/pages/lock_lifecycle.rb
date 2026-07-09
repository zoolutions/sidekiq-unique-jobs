# frozen_string_literal: true

class Views::Docs::Pages::LockLifecycle < DocsUI::Page
  title "Lock lifecycle"
  eyebrow "Concepts"

  def lead = "Every lock is born at a moment, held for a while, and released at a moment — and each lock type picks a different pair of moments."

  def content
    the_arc
    the_table
    acquire
    hold
    release
    after_unlock_callback
  end

  private

  def the_arc
    DocsUI::Section("The arc of a lock") do
      md <<~'MD'
        A lock has exactly three moments in its life:

        1. **Acquire** — the lock is created in Redis and starts blocking duplicates.
        2. **Hold** — the lock exists; any second copy with the same
           [digest](/docs/how-locking-works) is a conflict.
        3. **Release** — the lock is removed and duplicates are allowed again.

        What separates the five lock types is *when* acquire and release happen.
        Some acquire at enqueue (in the client middleware), some acquire on the
        server just before `perform`. Some release before the job runs, some after
        it finishes, some only when a TTL expires. Everything else — timeouts,
        conflict strategies, argument filtering — is tuning around these two
        moments.
      MD
    end
  end

  def the_table
    DocsUI::Section("The five lock types, at a glance", description: "Where each lock is born and where it dies.") do
      md <<~'MD'
        | Lock type | Locks at | Unlocks at | Prevents |
        |-----------|----------|------------|----------|
        | `:until_executing` | Enqueue (client) | Just **before** `perform` starts (server) | Duplicate enqueues while a copy is still queued |
        | `:until_executed` | Enqueue (client) | **After** `perform` completes (server) | Duplicates for the whole push → done lifecycle |
        | `:until_expired` | Enqueue (client) | When the TTL expires (never on completion) | Duplicates within a fixed time window |
        | `:while_executing` | Just **before** `perform` (server) | **After** `perform` (server) | Concurrent execution only — not enqueues |
        | `:until_and_while_executing` | Enqueue **and** before `perform` | Before `perform` **and** after `perform` | Duplicate enqueues **and** concurrent execution |

        See [Choosing a lock type](/docs/choosing-a-lock-type) for the "I want to
        prevent X" decision table. The rest of this page walks through each phase.
      MD
    end
  end

  def acquire
    DocsUI::Section("Acquire — where a lock is born") do
      md <<~'MD'
        A lock is acquired in one of two places, depending on its type.

        ### Client-side acquire (at enqueue)

        `:until_executing`, `:until_executed`, and `:until_expired` acquire the lock
        in the **client middleware**, the moment the job is pushed. If the lock is
        already held, the push is a duplicate and the conflict strategy decides its
        fate — see [Conflict resolution](/docs/conflict-resolution).
      MD

      DocsUI::Code(<<~RUBY)
        class GenerateReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(account_id)
            # The lock was acquired when this job was enqueued, and is
            # held until this method returns.
          end
        end
      RUBY

      md <<~'MD'
        ### Server-side acquire (just before perform)

        `:while_executing` does **not** touch enqueueing at all. Duplicates pile up
        in the queue freely; the lock is acquired on the **server**, right before
        `perform` runs, so only one copy executes at a time. A worker that waits for
        the lock is bounded by `lock_timeout` — see
        [TTL and timeouts](/docs/ttl-and-timeouts).
      MD

      DocsUI::Code(<<~RUBY)
        class RebuildSearchIndexJob
          include Sidekiq::Job

          sidekiq_options lock: :while_executing, lock_timeout: 5

          def perform
            # Many copies may sit in the queue; only one runs this body
            # at any given moment.
          end
        end
      RUBY

      md <<~'MD'
        `:until_and_while_executing` does both: it acquires at enqueue (like
        `:until_executed`) **and** acquires a second, execution-scoped lock just
        before `perform` — so the job is unique in the queue *and* serialized while
        running.
      MD
    end
  end

  def hold
    DocsUI::Section("Hold — while the lock exists") do
      md <<~'MD'
        While a lock is held, it lives as two Redis structures (see
        [How locking works](/docs/how-locking-works)):

        - `<digest>:LOCKED` — a hash of the job IDs holding this digest, with metadata.
        - `uniquejobs:digests` — a global sorted set indexing every active lock.

        Any second job whose class, queue, and arguments hash to the same digest is
        a conflict for as long as the lock is held. By default a digest allows a
        single holder; `lock_limit:` raises that ceiling so up to *N* copies can
        hold the same digest at once.
      MD

      DocsUI::Code(<<~RUBY)
        class SyncContactsJob
          include Sidekiq::Job

          # Allow up to 3 concurrent syncs for the same arguments.
          sidekiq_options lock: :while_executing, lock_limit: 3

          def perform(list_id)
            # Up to three copies may hold this lock simultaneously.
          end
        end
      RUBY

      DocsUI::Callout(:note) do
        plain "Uniqueness is decided by the digest — worker class, queue, and arguments. To make only some arguments count, use "
        a(href: "/docs/how-locking-works") { "lock_args_method" }
        plain "."
      end
    end
  end

  def release
    DocsUI::Section("Release — where a lock dies") do
      md <<~'MD'
        A lock is released in one of three ways, and the lock type chooses which.

        ### Before perform starts

        `:until_executing` releases the moment the server picks the job up, just
        **before** `perform` runs. Its whole purpose is to debounce a burst of
        enqueues: once a copy actually starts running, the queue is clear and a
        fresh copy may enqueue again.
      MD

      DocsUI::Code(<<~RUBY)
        class DeliverWebhookJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executing

          def perform(endpoint_id, payload)
            # The lock was already released before this line ran, so a new
            # webhook can queue up while this one delivers.
          end
        end
      RUBY

      md <<~'MD'
        ### After perform completes

        `:until_executed` (and the execution phase of
        `:until_and_while_executing`) releases **after** `perform` returns — the
        lock spans the entire push → done lifecycle. `:while_executing` also
        releases here, since it only ever existed for the duration of `perform`.

        ### When the TTL expires

        `:until_expired` never releases on completion. It lives exactly as long as
        `lock_ttl`, measured from when the lock was **created** at enqueue — not
        from when the job finishes. This is the lock for time-boxed uniqueness, like
        a "once per day" job.
      MD

      DocsUI::Code(<<~RUBY)
        class SendDailyDigestJob
          include Sidekiq::Job

          # One digest per user per day: the lock outlives the job and
          # expires 24 hours after it was enqueued.
          sidekiq_options lock: :until_expired, lock_ttl: 86_400

          def perform(user_id)
            # Enqueue this again within the TTL window and it's a duplicate,
            # whether or not this run has finished.
          end
        end
      RUBY

      DocsUI::Callout(:tip) do
        plain "lock_ttl bounds how long the lock lives; lock_timeout bounds how long a client waits to acquire a held lock. They're independent — see "
        a(href: "/docs/ttl-and-timeouts") { "TTL and timeouts" }
        plain "."
      end
    end
  end

  def after_unlock_callback
    DocsUI::Section("The after_unlock callback") do
      md <<~'MD'
        Right after a lock is released, the gem can call back into your worker.
        Define `after_unlock` as an instance or class method and it runs on
        release — useful for cleanup, metrics, or chaining follow-up work.
      MD

      DocsUI::Code(<<~RUBY)
        class ImportOrdersJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(batch_id)
            # ... import work ...
          end

          def after_unlock
            # Runs after the lock is released.
            Rails.logger.info("import lock released")
          end
        end
      RUBY

      DocsUI::Callout(:warning) do
        plain "after_unlock never fires for :until_expired. That lock is released by Redis expiring the key, not by your code running, so there is no release event to hook."
      end
    end
  end
end

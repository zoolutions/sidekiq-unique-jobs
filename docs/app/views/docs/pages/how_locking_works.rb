# frozen_string_literal: true

class Views::Docs::Pages::HowLockingWorks < DocsUI::Page
  title "How locking works"
  eyebrow "Concepts"

  def lead = "A lock is a digest of the job, stored as two Redis keys, taken and released atomically by Lua from the client or server middleware."

  def content
    the_digest
    the_two_keys
    atomicity
    client_and_server
  end

  private

  def the_digest
    DocsUI::Section("The digest: what \"the same job\" means", description: "Worker class, queue, and arguments, hashed into one key.") do
      md <<~'MD'
        Before anything can be locked, the gem has to answer one question: *is this
        job the same as one already running?* It answers it by building a **digest**
        — a hash computed from three things:

        - the **worker class** (`ChargeCustomerJob`),
        - the **queue** the job is on, and
        - the job's **arguments**.

        Two pushes that produce the same digest are considered the same job; two
        that differ are independent. So `ChargeCustomerJob.perform_async(1)` and
        `ChargeCustomerJob.perform_async(2)` never collide, but a second
        `perform_async(1)` while the first is still locked does.
      MD

      DocsUI::Code(<<~RUBY)
        class ChargeCustomerJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(customer_id)
            # digest = hash(worker class + queue + [customer_id])
          end
        end
      RUBY

      md <<~'MD'
        The digest is hashed with one of two algorithms, set globally via
        `config.digest_algorithm`: `:legacy` (MD5, the default) or `:modern`
        (a FIPS-friendly alternative). They produce different digests, so changing
        the algorithm re-keys every lock — pick one and leave it.

        Because *all* arguments feed the digest by default, a single transient
        value (a timestamp, a request id) makes every push unique and defeats the
        lock. When that happens, narrow what counts with
        [Custom uniqueness arguments](/docs/custom-uniqueness-arguments).
      MD

      DocsUI::Callout(:tip) do
        plain "Two options widen the digest instead of narrowing it: "
        plain "unique_across_queues ignores the queue, and unique_across_workers ignores the worker class — so the same arguments collide regardless of where or by whom they were enqueued."
      end
    end
  end

  def the_two_keys
    DocsUI::Section("Two Redis keys per lock") do
      md <<~'MD'
        Once the digest is known, a held lock is just two Redis structures. In v9
        that's the whole data model — no per-lock sprawl:
      MD

      DocsUI::Code(<<~TEXT, lexer: :text)
        <digest>:LOCKED       # Hash  — job_id => metadata, i.e. who holds this lock
        uniquejobs:digests    # ZSet  — a global index of every active digest
      TEXT

      md <<~'MD'
        - **`<digest>:LOCKED`** is a Redis **hash** keyed on the digest. Each entry
          maps a `job_id` to the metadata for the holder — this is what proves a
          lock is currently taken and by which job.
        - **`uniquejobs:digests`** is a single global **sorted set** that indexes
          every active digest, with the lock or expiry time as the score. It's what
          the reaper and the Web UI scan to find and clean up locks.

        `uniquejobs` is the default key prefix (`config.lock_prefix`); override it
        globally or per worker with `lock_prefix:`. For a `lock_ttl` lock the expiry
        time is stored as the digest's score in the same sorted set — there's no
        separate structure for expiring locks.
      MD

      DocsUI::Callout(:note) do
        plain "Coming from v8? A lock used to spread across as many as thirteen keys. v9 auto-migrates your existing lock data to these two on first startup — see "
        a(href: "/docs/upgrading-to-v9") { "Upgrading to v9" }
        plain "."
      end
    end
  end

  def atomicity
    DocsUI::Section("Atomic by Lua", description: "Acquire-or-fail is one script, so two racing pushes can't both win.") do
      md <<~'MD'
        The dangerous moment for any lock is the gap between *checking* whether it's
        free and *taking* it. If two duplicate enqueues both check "is this digest
        locked?" at the same instant, both see "no", and both proceed — the lock
        did nothing.

        sidekiq-unique-jobs closes that gap by running every lock operation as a
        single **Lua script** inside Redis. Acquiring a lock — read the hash, decide,
        write the holder — happens as one atomic step that Redis runs start-to-finish
        with nothing interleaved. Two racing pushes with the same digest hit the same
        script: exactly one writes itself into `<digest>:LOCKED` and wins, the other
        observes the lock is taken and is handled by its conflict strategy.

        Releasing works the same way: `unlock.lua` removes the holder and updates the
        digests index atomically, so a lock is never half-released. Every lifecycle
        primitive — lock, unlock, fetch, and the reaper's cleanup — is a script in
        `lib/sidekiq_unique_jobs/lua/`.
      MD
    end
  end

  def client_and_server
    DocsUI::Section("Where the lock is taken: client vs. server") do
      md <<~'MD'
        Sidekiq runs jobs through two middleware chains, and both are where the lock
        work happens:

        - The **client middleware** runs when a job is **enqueued** (`perform_async`).
        - The **server middleware** runs when a worker **executes** the job.

        The lock type decides which chain takes and releases the lock. A lock that
        prevents duplicate *enqueues* is taken on the client at push time; a lock
        that prevents concurrent *execution* is taken on the server, right before
        `perform`:
      MD

      DocsUI::PropTable([
        [ "Lock type", "Locks at", "Unlocks at" ],
        [ "until_executing", "Enqueue (client)", "Just before perform starts (server)" ],
        [ "until_executed", "Enqueue (client)", "After perform completes (server)" ],
        [ "until_expired", "Enqueue (client)", "When the TTL expires" ],
        [ "while_executing", "Just before perform (server)", "After perform (server)" ],
        [ "until_and_while_executing", "Enqueue (client) + before perform (server)", "Before perform + after perform (server)" ]
      ])

      md <<~'MD'
        This is why `while_executing` won't stop a duplicate from landing in the
        queue — it never touches the client chain, so the copy enqueues freely and
        is only serialized when it tries to run. And it's why the middleware must be
        installed on both chains for client-side locks to release on the server; the
        [Installation](/docs/installation) initializer wires up both.

        For the exact acquire-and-release timeline of each lock type — including
        when the `after_unlock` callback fires — see [Lock lifecycle](/docs/lock-lifecycle).
      MD
    end
  end
end

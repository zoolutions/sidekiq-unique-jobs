# frozen_string_literal: true

class Views::Docs::Pages::CustomUniquenessArguments < DocsUI::Page
  title "Custom uniqueness arguments"
  eyebrow "Use cases"

  def lead = "Choose exactly which arguments — and which parts of the digest — decide whether two jobs count as the same."

  def content
    the_problem
    class_method_form
    lambda_form
    across_queues_and_workers
    digest_algorithm
    where_to_go
  end

  private

  def the_problem
    DocsUI::Section("The problem: a transient argument", description: "Only the arguments that matter should count.") do
      md <<~'MD'
        By default a job's uniqueness digest is built from three things: the
        **worker class**, the **queue**, and **all of the arguments**. That's the
        right default, but it breaks the moment an argument carries something
        transient — a timestamp, a request ID, a retry counter — that changes on
        every call yet has nothing to do with whether two jobs are "the same".

        Consider a job that refreshes a user's cache. It takes the `user_id` that
        actually identifies the work, plus an `enqueued_at` timestamp used only for
        logging:
      MD

      DocsUI::Code(<<~RUBY)
        RefreshUserCacheJob.perform_async(42, "2026-07-09T10:00:00Z")
        RefreshUserCacheJob.perform_async(42, "2026-07-09T10:00:01Z")
      RUBY

      md <<~'MD'
        These are the same piece of work — user `42` — but because the timestamps
        differ, the default digest treats them as two distinct jobs and both get
        enqueued. The fix is to tell the gem which arguments matter with
        **`lock_args_method`**: a hook that receives the full args array and
        returns just the subset that should drive uniqueness.
      MD
    end
  end

  def class_method_form
    DocsUI::Section("As a class method", description: "A symbol naming a class method on the worker.") do
      md <<~'MD'
        Point `lock_args_method:` at a symbol naming a class method. The method
        receives the full arguments array and returns the subset that defines
        uniqueness — here, just the first argument:
      MD

      DocsUI::Code(<<~RUBY)
        class RefreshUserCacheJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, lock_args_method: :unique_args

          def self.unique_args(args)
            [args.first]
          end

          def perform(user_id, _enqueued_at)
            # Only one refresh per user_id is in flight at a time,
            # no matter what timestamp was passed alongside it.
          end
        end
      RUBY

      md <<~'MD'
        Now `perform_async(42, <any timestamp>)` produces the same digest every
        time, so the second enqueue while the first is still locked is recognised
        as a duplicate.
      MD
    end
  end

  def lambda_form
    DocsUI::Section("As a lambda", description: "An inline proc when a named method is overkill.") do
      md <<~'MD'
        For a one-liner you don't want to name, pass a lambda directly. It takes
        the args array and returns the subset — exactly like the class method:
      MD

      DocsUI::Code(<<~RUBY)
        class RefreshUserCacheJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed,
                          lock_args_method: ->(args) { [args.first] }

          def perform(user_id, _enqueued_at)
            # Same effect as the class-method form above.
          end
        end
      RUBY

      DocsUI::Callout(:tip) do
        plain "Return the smallest set of values that truly identifies the work. Anything you leave out is invisible to uniqueness; anything you leave in splits jobs that you might have wanted to treat as one."
      end
    end
  end

  def across_queues_and_workers
    DocsUI::Section("Widening the net: queues and workers") do
      md <<~'MD'
        Filtering arguments narrows what counts as a duplicate. Two options do the
        opposite — they *remove* a dimension from the digest so that more jobs
        collide into the same lock.

        ### `unique_across_queues`

        By default the queue is part of the digest, so the same job on `default`
        and on `low` are independent. Set `unique_across_queues: true` to ignore
        the queue — the same arguments on **any** queue are one lock:
      MD

      DocsUI::Code(<<~RUBY)
        class RefreshUserCacheJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed,
                          lock_args_method: :unique_args,
                          unique_across_queues: true

          def self.unique_args(args)
            [args.first]
          end

          def perform(user_id, _enqueued_at)
            # Unique per user_id regardless of which queue the job lands on.
          end
        end
      RUBY

      md <<~'MD'
        ### `unique_across_workers`

        By default the worker class is part of the digest, so two different worker
        classes never share a lock even with identical arguments. Set
        `unique_across_workers: true` to drop the class from the digest, so
        different workers with the same arguments count as duplicates. This one is
        typically set on **both** workers you want to deduplicate against each
        other:
      MD

      DocsUI::Code(<<~RUBY)
        class RefreshUserCacheJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, unique_across_workers: true

          def perform(user_id)
            # Shares a lock with any other worker that also opts in.
          end
        end
      RUBY
    end
  end

  def digest_algorithm
    DocsUI::Section("A note on the digest algorithm") do
      md <<~'MD'
        Whatever arguments survive filtering are hashed into the digest string.
        Two algorithms are available, chosen globally via
        `config.digest_algorithm`:

        - **`:legacy`** — MD5-based. The default.
        - **`:modern`** — a FIPS-friendly alternative for environments where MD5
          is unavailable.

        The choice is invisible day to day, but note that **changing it changes
        every digest**, so locks created under one algorithm won't match locks
        created under the other. Pick one before you go to production and leave it
        alone.
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.configure do |config|
          config.digest_algorithm = :modern
        end
      RUBY
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[How locking works](/docs/how-locking-works)** — what the digest is and
          how the lock is acquired and released.
        - **[Worker options](/docs/worker-options)** — the full reference for
          `lock_args_method`, `unique_across_queues`, `unique_across_workers`, and
          every other `sidekiq_options` key.
      MD
    end
  end
end

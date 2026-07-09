# frozen_string_literal: true

class Views::Docs::Pages::Overview < DocsUI::Page
  title "Overview"
  eyebrow "Getting started"

  def lead = "sidekiq-unique-jobs stops the same job from being enqueued twice or run concurrently, using Redis locks keyed on the job's arguments."

  def content
    what_it_does
    the_two_questions
    two_keys
    where_to_go
  end

  private

  def what_it_does
    DocsUI::Section("What it does") do
      md <<~'MD'
        Sidekiq will happily enqueue the same job a hundred times. Usually that's
        fine — but sometimes it isn't: a webhook that fires twice, a user who
        double-clicks "export", a cron tick that overlaps the previous run.
        sidekiq-unique-jobs makes a job **unique**: while a lock is held, a second
        copy with the same arguments is prevented (or logged, rejected,
        rescheduled — your choice).

        A job opts in with one line:
      MD

      DocsUI::Code(<<~RUBY)
        class ChargeCustomerJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(customer_id)
            # Only one job per customer_id at a time.
          end
        end
      RUBY

      md <<~'MD'
        Uniqueness is based on the worker class, the queue, and the arguments —
        so `ChargeCustomerJob.perform_async(1)` and `ChargeCustomerJob.perform_async(2)`
        are independent, but a second `perform_async(1)` while the first is still
        locked is a duplicate.
      MD
    end
  end

  def the_two_questions
    DocsUI::Section("Two questions decide everything", description: "Which lock type, and what happens on a conflict.") do
      md <<~'MD'
        Configuring a unique job comes down to two decisions:

        1. **When should the lock be held?** From enqueue until the job starts?
           Until it finishes? For a fixed time window? Only while it runs? That's
           the *lock type* — see [Choosing a lock type](/docs/choosing-a-lock-type).
        2. **What should happen to a duplicate?** Drop it, retry it later, replace
           the original, or send it to the dead set? That's the *conflict
           strategy* — see [Conflict resolution](/docs/conflict-resolution).

        Everything else — TTLs, timeouts, custom argument filtering, concurrency
        limits — is tuning on top of those two.
      MD
    end
  end

  def two_keys
    DocsUI::Section("Two Redis keys per lock") do
      md <<~'MD'
        v9 is a ground-up rewrite. A lock is now just two Redis structures:
      MD

      DocsUI::Code(<<~TEXT, lexer: :text)
        <digest>:LOCKED       # Hash  — the job IDs holding this lock, with metadata
        uniquejobs:digests    # ZSet  — a global index of every active lock
      TEXT

      md <<~'MD'
        Every lock operation runs inside a Lua script, so acquiring and releasing
        a lock is atomic even under heavy contention. If you're coming from v8,
        that's down from as many as thirteen keys per lock — see
        [Upgrading to v9](/docs/upgrading-to-v9).
      MD

      DocsUI::Callout(:note) do
        plain "The middleware is not loaded automatically. You add it once in your Sidekiq initializer — see "
        a(href: "/docs/installation") { "Installation" }
        plain "."
      end
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[Installation](/docs/installation)** — add the gem and wire up the middleware.
        - **[Quick start](/docs/quick-start)** — your first unique job in five minutes.
        - **[Use cases](/docs/debounce-duplicate-enqueues)** — pick the page that
          matches what you're trying to prevent; each one is a complete, working worker.
        - **[Choosing a lock type](/docs/choosing-a-lock-type)** — a decision table
          from "I want to prevent X" to the lock that does it.
      MD
    end
  end
end

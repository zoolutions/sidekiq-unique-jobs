# frozen_string_literal: true

class Views::Docs::Pages::QuickStart < DocsUI::Page
  title "Quick start"
  eyebrow "Getting started"

  def lead = "From a plain Sidekiq worker to a deduplicated one in five minutes — write it, watch a duplicate get dropped, then change what happens instead."

  def content
    before_you_start
    first_unique_worker
    watch_the_duplicate_drop
    change_the_outcome
    where_to_go
  end

  private

  def before_you_start
    DocsUI::Section("Before you start") do
      md <<~'MD'
        This page assumes the middleware is already wired into your Sidekiq
        initializer. If you haven't done that yet, it's a one-time copy-paste —
        see [Installation](/docs/installation). Nothing on this page works until
        the client and server middleware are registered.
      MD
    end
  end

  def first_unique_worker
    DocsUI::Section("1. Write a unique worker", description: "One line of sidekiq_options opts a worker into uniqueness.") do
      md <<~'MD'
        Take an ordinary worker and add a `lock:`. We'll use `:until_executed`,
        which holds the lock from the moment the job is enqueued until `perform`
        finishes — so no duplicate can slip in for the entire lifecycle of the
        job.
      MD

      DocsUI::Code(<<~RUBY)
        class SendWelcomeEmailJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(user_id)
            user = User.find(user_id)
            WelcomeMailer.welcome(user).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        That's the whole change. Uniqueness is keyed on the worker class, the
        queue, and the arguments — so `SendWelcomeEmailJob.perform_async(1)` and
        `SendWelcomeEmailJob.perform_async(2)` are two independent jobs, while a
        second `perform_async(1)` fired before the first has run is a duplicate.
      MD
    end
  end

  def watch_the_duplicate_drop
    DocsUI::Section("2. Enqueue it twice", description: "The second push, while the first is locked, is dropped.") do
      md <<~'MD'
        Enqueue the same arguments twice in a row. The first call acquires the
        lock and returns a job ID; the second finds the lock already held and is
        discarded, returning `nil`.
      MD

      DocsUI::Code(<<~RUBY)
        SendWelcomeEmailJob.perform_async(1) # => "a1b2c3..."  enqueued, lock acquired
        SendWelcomeEmailJob.perform_async(1) # => nil          duplicate, dropped
        SendWelcomeEmailJob.perform_async(2) # => "d4e5f6..."  different args, enqueued
      RUBY

      md <<~'MD'
        Dropping the duplicate is the default because no `on_conflict` strategy
        was set — the conflict is logged and the extra job is discarded. Once the
        first job runs to completion the lock is released, and
        `perform_async(1)` will enqueue normally again.
      MD

      DocsUI::Callout(:tip) do
        plain "Uniqueness is enforced even in tests. "
        plain "Sidekiq::Testing.inline! runs jobs immediately with locking still in effect, so you can drive this exact behavior in a console or spec."
      end
    end
  end

  def change_the_outcome
    DocsUI::Section("3. Change what happens on a conflict", description: "Reschedule the duplicate instead of dropping it.") do
      md <<~'MD'
        Dropping is not always what you want. Add `on_conflict:` to choose a
        different outcome. With `:reschedule`, the duplicate isn't thrown
        away — it's re-enqueued to run later, so it still happens once the lock
        clears.
      MD

      DocsUI::Code(<<~RUBY)
        class SendWelcomeEmailJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed, on_conflict: :reschedule

          def perform(user_id)
            user = User.find(user_id)
            WelcomeMailer.welcome(user).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        Now the second `perform_async(1)` is re-enqueued to run later rather than
        dropped. The other strategies cover the rest of the spectrum: `:raise`
        makes Sidekiq retry the job, `:reject` sends the duplicate to the Dead
        set, and `:replace` deletes the original and enqueues the new one. See
        [Conflict resolution](/docs/conflict-resolution) for the full table.
      MD
    end
  end

  def where_to_go
    DocsUI::Section("Where to go next") do
      md <<~'MD'
        - **[Choosing a lock type](/docs/choosing-a-lock-type)** — a decision
          table from "I want to prevent X" to the lock that does it. `:until_executed`
          is one of five.
        - **[Use cases](/docs/debounce-duplicate-enqueues)** — start with
          debouncing duplicate enqueues; each use-case page is a complete,
          working worker you can lift straight into your app.
      MD
    end
  end
end

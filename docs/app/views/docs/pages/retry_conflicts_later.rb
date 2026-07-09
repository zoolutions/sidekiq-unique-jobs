# frozen_string_literal: true

class Views::Docs::Pages::RetryConflictsLater < DocsUI::Page
  title "Retry conflicts later"
  eyebrow "Use cases"

  def lead = "When a polling or cron job overlaps its previous run, reschedule the duplicate to run later instead of dropping it."

  def content
    the_problem
    the_worker
    walkthrough
    observability
    contrast_with_raise
  end

  private

  def the_problem
    DocsUI::Section("The problem") do
      md <<~'MD'
        You have a job that polls an external system on a schedule — every minute,
        say, a cron entry kicks off `PollProviderStatusJob`. Most runs finish in a
        second. But when the provider is slow, a run can take longer than a minute,
        and the next tick enqueues a second copy while the first is still working.

        You don't want two copies polling at once. But you also don't want to
        **discard** the second tick — the poll still needs to happen, just not
        *right now*. Dropping it (the default `:log` behavior) means a missed
        interval. What you want is: skip the overlap, and run the duplicate a
        little later, once the original is out of the way.

        That's `on_conflict: :reschedule`.
      MD
    end
  end

  def the_worker
    DocsUI::Section("A complete worker", description: "until_executed keeps it unique for the whole run; reschedule re-enqueues the loser.") do
      DocsUI::Code(<<~RUBY)
        class PollProviderStatusJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed,
                          on_conflict: :reschedule

          def perform(provider_id)
            status = ProviderClient.new(provider_id).fetch_status
            ProviderStatus.record!(provider_id, status)
          end
        end
      RUBY

      md <<~'MD'
        `lock: :until_executed` holds the lock from the moment the job is enqueued
        until `perform` finishes — so while one poll for a given `provider_id` is
        in flight, a second one with the same `provider_id` is a conflict. See
        [Choosing a lock type](/docs/choosing-a-lock-type) for why this is the
        right lock for overlapping runs.

        `on_conflict: :reschedule` decides what happens to that second copy: rather
        than being logged and dropped, it is **re-enqueued to run later**.
      MD
    end
  end

  def walkthrough
    DocsUI::Section("What happens on an overlap") do
      md <<~'MD'
        Walk through two ticks landing while a poll for `provider_id = 42` is
        already running:

        1. **12:00:00** — the cron tick enqueues `PollProviderStatusJob` with
           `provider_id = 42`. It acquires the lock and starts polling. The
           provider is slow today.
        2. **12:01:00** — the next tick enqueues the same job with the same
           `provider_id`. The lock is still held, so this is a conflict.
        3. Because `on_conflict: :reschedule` is set, the duplicate is **not
           discarded** — it is re-enqueued to run later, after the current holder
           has had a chance to finish.
        4. When it runs later, the original has completed and released the lock, so
           the rescheduled copy acquires the lock cleanly and does its poll.

        No interval is silently lost: every tick eventually runs, they just never
        run on top of each other.
      MD

      DocsUI::Callout(:tip) do
        plain "Reschedule pairs naturally with cron/polling jobs where every run matters but overlap is harmful. If a dropped duplicate is fine — a debounce where the newest enqueue wins — the default is simpler; see "
        a(href: "/docs/conflict-resolution") { "Conflict resolution" }
        plain "."
      end
    end
  end

  def observability
    DocsUI::Section("Watching reschedules happen") do
      md <<~'MD'
        Two [reflections](/docs/observability) fire around this strategy, so you
        can see how often overlaps occur and catch the rare case where the
        re-enqueue itself fails:

        - `rescheduled` — a duplicate was successfully re-enqueued to run later.
        - `reschedule_failed` — the re-enqueue could not be performed.

        A steady stream of `rescheduled` events for one `provider_id` is a signal
        that your interval is too tight for how long that poll actually takes.
      MD

      DocsUI::Code(<<~'RUBY')
        SidekiqUniqueJobs.reflect do |on|
          on.rescheduled do |job_hash|
            StatsD.increment("uniquejobs.rescheduled", tags: ["class:#{job_hash["class"]}"])
          end

          on.reschedule_failed do |job_hash|
            Sidekiq.logger.warn("could not reschedule #{job_hash["class"]}")
          end
        end
      RUBY
    end
  end

  def contrast_with_raise
    DocsUI::Section("Reschedule vs. raise") do
      md <<~'MD'
        `:reschedule` and `:raise` both give the duplicate another chance to run,
        but through different machinery:

        - **`:reschedule`** re-enqueues the duplicate itself to run later. This is a
          fresh enqueue, not a Sidekiq retry, so it doesn't consume the job's retry
          budget and doesn't apply Sidekiq's exponential backoff. Best when the
          work must happen and overlaps are expected and benign — polling, cron.
        - **`:raise`** raises on the conflict so **Sidekiq** retries the job later,
          with its normal exponential backoff and retry limits. Best when a
          conflict is unusual and you want Sidekiq's retry/backoff/dead-set
          machinery to handle it — see [Conflict resolution](/docs/conflict-resolution).

        For a predictable, ever-present schedule where you simply want the loser to
        try again soon, `:reschedule` is the more natural fit. When a collision is
        an exceptional event you'd want to see backed off and eventually dead-set,
        reach for `:raise`.
      MD
    end
  end
end

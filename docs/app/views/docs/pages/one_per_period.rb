# frozen_string_literal: true

class Views::Docs::Pages::OnePerPeriod < DocsUI::Page
  title "One per period"
  eyebrow "Use cases"

  def lead = "Send a job at most once per key per fixed time window — one digest email per user per day — with :until_expired and a lock_ttl that matches the period."

  def content
    the_scenario
    the_worker
    how_it_works
    picking_the_ttl
    after_unlock_note
  end

  private

  def the_scenario
    DocsUI::Section("The scenario") do
      md <<~'MD'
        You send a daily digest email. The job that enqueues it can fire more than
        once a day — a cron tick overlaps, a backfill re-runs, a retry loops — but
        each user must receive **at most one** digest per calendar day, no matter
        how many times the job is scheduled.

        This is *time-boxed uniqueness*: the same arguments are a duplicate for a
        fixed window, then the window resets. The `:until_expired` lock does exactly
        that. The lock is created when the job is enqueued and lives for `lock_ttl`
        seconds — a full day — regardless of when, or whether, the job actually runs.
        Any second enqueue for the same user inside that window is a duplicate.
      MD
    end
  end

  def the_worker
    DocsUI::Section("The worker", description: "One user, one digest, one day.") do
      DocsUI::Code(<<~RUBY)
        class DailyDigestJob
          include Sidekiq::Job

          sidekiq_options lock: :until_expired, lock_ttl: 86_400

          def perform(user_id)
            user = User.find(user_id)
            DigestMailer.daily(user).deliver_now
          end
        end
      RUBY

      md <<~'MD'
        `DailyDigestJob.perform_async(42)` acquires a lock keyed on the worker
        class, the queue, and the argument `42`. For the next `86_400` seconds — one
        day — every further `DailyDigestJob.perform_async(42)` sees that lock and is
        discarded (the default conflict behavior is to log and drop the duplicate).
        A different user, `perform_async(43)`, has different arguments and its own
        independent lock.
      MD
    end
  end

  def how_it_works
    DocsUI::Section("How the window works") do
      md <<~'MD'
        `:until_expired` is unusual among the lock types: it is the only one that
        never unlocks on the job's behalf. The lifecycle is entirely driven by the
        TTL.

        1. **Enqueue.** The client middleware creates the lock and stamps it with a
           TTL of `lock_ttl` seconds. This happens on the push, before any worker
           picks the job up.
        2. **Execution.** The job runs (or fails, or never runs at all). Either way,
           **the lock is not released when the job finishes** — running the job does
           not shorten or extend the window.
        3. **Expiry.** When `lock_ttl` seconds have elapsed *from the moment the lock
           was created*, Redis expires the lock. Only now can the next enqueue for
           the same user acquire a fresh lock and send tomorrow's digest.

        So the guarantee is "one per window", not "one at a time": within a single
        `lock_ttl` window, exactly one enqueue wins and the rest are duplicates.
      MD

      DocsUI::Callout(:warning) do
        plain "The TTL counts from lock creation, not from job completion. A digest scheduled at 09:00 unlocks 24 hours after 09:00 — not 24 hours after the mail was sent. If you need the clock to start when the job finishes, this is the wrong lock type; see "
        a(href: "/docs/ttl-and-timeouts") { "TTL and timeouts" }
        plain "."
      end
    end
  end

  def picking_the_ttl
    DocsUI::Section("Picking the TTL") do
      md <<~'MD'
        The `lock_ttl` *is* the period. Choose it to match the window you want to
        deduplicate, in seconds:
      MD

      DocsUI::PropTable([
        [ "Once per hour", "Integer", "3_600", "Rolling one-hour window from first enqueue" ],
        [ "Once per day", "Integer", "86_400", "The daily digest above" ],
        [ "Once per week", "Integer", "604_800", "Weekly summary" ]
      ])

      DocsUI::Callout(:tip) do
        plain "Match the TTL to the period, and enqueue on a schedule aligned to that period. Because the window starts at the first enqueue rather than at a calendar boundary, a job enqueued at 23:59 unlocks at 23:59 the next day — pick a stable enqueue time (a single daily cron) so the window lines up with your intended cadence."
      end
    end
  end

  def after_unlock_note
    DocsUI::Section("No after_unlock callback") do
      md <<~'MD'
        Because the lock is released by Redis expiry and not by your code, an
        `:until_expired` lock **never** invokes the `after_unlock` callback. There is
        no moment in your worker where the release happens, so there is nothing to
        hook. If you need cleanup to run when a job's lock is released, use a lock
        that unlocks on completion — `:until_executed` — instead.

        For the full map of when each lock acquires and releases, see
        [Choosing a lock type](/docs/choosing-a-lock-type).
      MD
    end
  end
end

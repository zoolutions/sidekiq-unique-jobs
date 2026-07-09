# frozen_string_literal: true

class Views::Docs::Pages::Reflections < DocsUI::Page
  title "Reflections"
  eyebrow "Reference"

  def lead = "Reflections are the observability hooks the gem calls at every point in a lock's lifecycle — subscribe to them to feed metrics, logs, and alerts."

  def content
    what_they_are
    registering
    events
    error_events
  end

  private

  def what_they_are
    DocsUI::Section("What reflections are") do
      md <<~'MD'
        The gem never logs or reports on your behalf beyond a bare minimum. Instead,
        it *reflects* — at each significant moment (a lock acquired, a lock that
        failed, a duplicate dropped, a callback that blew up) it invokes the handler
        you registered for that event. You decide what happens: increment a StatsD
        counter, write a structured log line, page someone.

        Every handler receives the Sidekiq job hash. Some events pass a second
        argument, the exception, so you can record the cause — but which events
        do, and whether the exception is actually present, varies. See the tables
        below for the honest per-event picture.

        For the bigger picture — wiring these into your metrics stack and what each
        event tells you operationally — see [Observability](/docs/observability).
      MD
    end
  end

  def registering
    DocsUI::Section("Registering handlers", description: "Pass a block to SidekiqUniqueJobs.reflect and attach a handler per event.") do
      md <<~'MD'
        Call `SidekiqUniqueJobs.reflect` with a block. The block is handed a
        subscriber (`on`); call the event name on it with your handler block.
        Register only the events you care about — anything you leave unregistered
        is simply not reported.
      MD

      DocsUI::Code(<<~'RUBY')
        SidekiqUniqueJobs.reflect do |on|
          on.locked do |job_hash|
            StatsD.increment("uniquejobs.locked")
          end

          on.lock_failed do |job_hash|
            Rails.logger.warn("lock failed: #{job_hash["class"]}")
          end

          on.unlocked do |job_hash|
            StatsD.increment("uniquejobs.unlocked")
          end

          on.execution_failed do |job_hash, exception|
            Sentry.capture_exception(exception, extra: { job: job_hash })
          end
        end
      RUBY

      DocsUI::Callout(:warning) do
        plain "A block is required. Calling SidekiqUniqueJobs.reflect without one raises NoBlockGiven."
      end

      md <<~'MD'
        Put the registration wherever your app boots — a Rails initializer such as
        `config/initializers/sidekiq_unique_jobs.rb` is the natural home. Calling
        `reflect` again adds to the existing handlers rather than replacing them.
      MD
    end
  end

  def events
    DocsUI::Section("The events", description: "All 14 reflection events and what each one means.") do
      md <<~'MD'
        Each handler is called with the job hash. A few events pass a second
        argument, but only one — `after_unlock_callback_failed` — reliably
        carries an exception. The **2nd arg** column below is honest about what
        you actually receive; see the section that follows for the details.
      MD

      DocsUI::PropTable([
        [ "locked", "job_hash", "—", "A lock was acquired successfully." ],
        [ "unlocked", "job_hash", "—", "A lock was released successfully." ],
        [ "lock_failed", "job_hash", "—", "The lock could not be acquired." ],
        [ "unlock_failed", "job_hash", "—", "The lock could not be released." ],
        [ "timeout", "job_hash", "—", "Lock acquisition was reported as timed out." ],
        [ "duplicate", "job_hash", "—", "A duplicate job was detected while the lock was held." ],
        [ "rescheduled", "job_hash", "—", "A conflicting job was re-enqueued to run later." ],
        [ "reschedule_failed", "job_hash", "—", "Rescheduling a conflicting job failed (no exception is passed)." ],
        [ "execution_failed", "job_hash", "exception (may be nil)", "The job raised an error while the lock was held. Only until_executing and until_executed pass the exception; the other lock types pass the job hash alone." ],
        [ "after_unlock_callback_failed", "job_hash", "exception", "A worker's after_unlock callback raised an error. Always carries the exception." ],
        [ "error", "job_hash", "exception", "Registerable for an unexpected internal error, but the gem does not currently emit this event." ],
        [ "uniqueness_lapsed", "job_hash", "—", "A lock expired or was gone before the job could use it." ],
        [ "unknown_sidekiq_worker", "job_hash", "—", "A job referenced a worker class that could not be resolved." ],
        [ "debug", "job_hash", "—", "A low-level debugging trace (verbose; opt in deliberately)." ]
      ])
    end
  end

  def error_events
    DocsUI::Section("Error events and the exception argument") do
      md <<~'MD'
        Only `after_unlock_callback_failed` **always** hands your block the
        exception that was raised. The rest are more nuanced:

        - `after_unlock_callback_failed` — always passes the exception. A worker's
          `after_unlock` callback blew up.
        - `execution_failed` — passes the exception for the `until_executing` and
          `until_executed` lock types only. For every other lock type the second
          argument is **nil**, so guard against it.
        - `reschedule_failed` — passes only the job hash; there is no exception
          argument.
        - `error` — is registerable and would carry an exception, but the gem does
          not currently emit it anywhere, so a handler for it never fires today.

        Whenever you touch the second argument, treat it as possibly nil so a
        failure inside the locking machinery isn't turned into a new one.
      MD

      DocsUI::Code(<<~'RUBY')
        SidekiqUniqueJobs.reflect do |on|
          # Always carries the exception.
          on.after_unlock_callback_failed do |job_hash, exception|
            Rails.logger.error(
              "after_unlock failed for #{job_hash["class"]}: #{exception.message}",
            )
          end

          # The exception may be nil depending on the lock type — guard for it.
          on.execution_failed do |job_hash, exception|
            if exception
              Sentry.capture_exception(exception, extra: { job: job_hash })
            else
              Rails.logger.error("execution failed for #{job_hash["class"]}")
            end
          end
        end
      RUBY

      DocsUI::Callout(:tip) do
        plain "Registering the error events is the cheapest way to surface problems the gem would otherwise handle quietly. See "
        a(href: "/docs/observability") { "Observability" }
        plain " for a full metrics setup."
      end
    end
  end
end

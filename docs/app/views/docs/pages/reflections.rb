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

        Every handler receives the Sidekiq job hash. Error-related events receive a
        second argument, the exception, so you can record the cause.

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
        Each handler is called with the job hash. The four **error** events also
        receive an exception as a second argument — see below.
      MD

      DocsUI::PropTable([
        [ "locked", "job_hash", "—", "A lock was acquired successfully." ],
        [ "unlocked", "job_hash", "—", "A lock was released successfully." ],
        [ "lock_failed", "job_hash", "—", "The lock could not be acquired." ],
        [ "unlock_failed", "job_hash", "—", "The lock could not be released." ],
        [ "timeout", "job_hash", "—", "Waiting for a contended lock exceeded lock_timeout." ],
        [ "duplicate", "job_hash", "—", "A duplicate job was detected while the lock was held." ],
        [ "rescheduled", "job_hash", "—", "A conflicting job was re-enqueued to run later." ],
        [ "reschedule_failed", "error", "exception", "Rescheduling a conflicting job failed." ],
        [ "execution_failed", "error", "exception", "The job raised an error while the lock was held." ],
        [ "after_unlock_callback_failed", "error", "exception", "A worker's after_unlock callback raised an error." ],
        [ "error", "error", "exception", "An unexpected internal error occurred." ],
        [ "uniqueness_lapsed", "job_hash", "—", "A lock expired or was gone before the job could use it." ],
        [ "unknown_sidekiq_worker", "job_hash", "—", "A job referenced a worker class that could not be resolved." ],
        [ "debug", "job_hash", "—", "A low-level debugging trace (verbose; opt in deliberately)." ]
      ])
    end
  end

  def error_events
    DocsUI::Section("Error events carry the exception") do
      md <<~'MD'
        Four events — `reschedule_failed`, `execution_failed`,
        `after_unlock_callback_failed`, and `error` — hand your block a second
        argument: the exception that was raised. Everything else receives the job
        hash alone. Capture the exception where you can, so a failure inside the
        locking machinery isn't silent.
      MD

      DocsUI::Code(<<~'RUBY')
        SidekiqUniqueJobs.reflect do |on|
          on.after_unlock_callback_failed do |job_hash, exception|
            Rails.logger.error(
              "after_unlock failed for #{job_hash["class"]}: #{exception.message}",
            )
          end

          on.error do |job_hash, exception|
            Sentry.capture_exception(exception, extra: { job: job_hash })
          end
        end
      RUBY

      DocsUI::Callout(:tip) do
        plain "Registering the four error events is the cheapest way to surface problems the gem would otherwise handle quietly. See "
        a(href: "/docs/observability") { "Observability" }
        plain " for a full metrics setup."
      end
    end
  end
end

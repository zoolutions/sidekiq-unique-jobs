# frozen_string_literal: true

class Views::Docs::Pages::Reliablefetch < DocsUI::Page
  title "ReliableFetch"
  eyebrow "Concepts"

  def lead = "An opt-in v9 fetch strategy that moves jobs into a per-process working list so a crash never loses a job — and never leaves a stale unique lock behind."

  def content
    the_problem
    opting_in
    how_it_works
    extra_keys
  end

  private

  def the_problem
    DocsUI::Section("Why reliable fetch") do
      md <<~'MD'
        Sidekiq's default fetch pops a job off its queue with a single `BRPOP`.
        The job is gone from the queue the instant it's fetched, before your
        worker has done anything with it. If the process dies at that
        moment — an `OOM` kill, a deploy that pulls the rug out, a hard crash —
        the job is simply lost.

        For a unique job that's doubly bad: the lock the job was holding is now
        orphaned, so future duplicates keep getting rejected against a job that
        will never run again. ReliableFetch closes both gaps at once. It's an
        alternative fetch strategy that never removes a job from Redis until the
        job is genuinely finished, and it understands uniqueness locks while it
        does so.
      MD

      DocsUI::Callout(:note) do
        plain "ReliableFetch is entirely optional. Sidekiq's default fetch works fine with unique jobs — the "
        a(href: "/docs/orphaned-locks-and-recovery") { "reaper" }
        plain " already cleans up orphaned locks. Reach for ReliableFetch when losing an in-flight job is unacceptable."
      end
    end
  end

  def opting_in
    DocsUI::Section("Opting in", description: "One line in your server configuration.") do
      md <<~'MD'
        Set the fetch class on the server. This applies to job execution only, so
        it goes in `configure_server`:
      MD

      DocsUI::Code(<<~RUBY)
        # config/initializers/sidekiq.rb
        Sidekiq.configure_server do |config|
          config[:fetch_class] = SidekiqUniqueJobs::Fetch::Reliable
        end
      RUBY

      md <<~'MD'
        That's the whole change. Your workers don't need to know about it — they
        keep declaring `sidekiq_options lock: :until_executed` (or any lock type)
        exactly as before:
      MD

      DocsUI::Code(<<~RUBY)
        class GenerateInvoiceJob
          include Sidekiq::Job

          sidekiq_options queue: :billing, lock: :until_executed

          def perform(invoice_id)
            # If this process crashes mid-run, ReliableFetch requeues the job
            # on the next startup — and the lock rides along with it.
            Invoice.find(invoice_id).generate!
          end
        end
      RUBY
    end
  end

  def how_it_works
    DocsUI::Section("The four guarantees") do
      md <<~'MD'
        ReliableFetch is built from four cooperating behaviors. Together they give
        you at-least-once delivery that respects unique locks.

        ### 1. Atomic fetch with `LMOVE`

        Instead of popping a job off the queue and holding it only in process
        memory, ReliableFetch uses a single atomic `LMOVE` to move the job from
        its queue directly onto a **per-process working list**
        (`uniquejobs:working:<identity>`). The job is never in a state where it's
        absent from both the queue and Redis. If the process dies the instant
        after the `LMOVE`, the job is safe on the working list.

        ### 2. Startup recovery of dead processes' jobs

        When a Sidekiq process boots, ReliableFetch looks for working lists left
        behind by processes that are no longer alive and moves their abandoned
        jobs back onto their queues. A crash doesn't strand a job forever — the
        next process to start picks up where the dead one left off.

        ### 3. Lock-aware acknowledge

        When a job finishes successfully, ReliableFetch removes it from the
        working list and confirms the uniqueness lock is cleaned up in the same
        step. The acknowledge understands locks, so a completed job never leaves a
        dangling lock on the working list.

        ### 4. Lock-preserving requeue on shutdown

        On a clean shutdown, any jobs still on the working list are requeued so
        they'll run again — and the requeue **preserves the lock**. The requeued
        copy is still the same unique job, so a duplicate enqueued in the meantime
        stays blocked rather than sneaking in alongside the recovered job.
      MD
    end
  end

  def extra_keys
    DocsUI::Section("The extra Redis keys") do
      md <<~'MD'
        A normal v9 lock is just two Redis structures (see the
        [Overview](/docs/overview)). ReliableFetch adds two more per process —
        keyed by the process **identity** (`hostname:pid:random-hex`), not by
        the digest. The trailing random hex suffix disambiguates a restarted
        process from a stale working list left behind on the same host and pid,
        so recovery never confuses the two:
      MD

      DocsUI::Code(<<~TEXT, lexer: :text)
        uniquejobs:working:<identity>     # List — jobs this process is currently running
        uniquejobs:heartbeat:<identity>   # liveness heartbeat used to detect dead processes
      TEXT

      md <<~'MD'
        The **working list** holds the in-flight jobs that recovery and requeue
        act on. The **heartbeat** is how startup recovery tells a live process
        from a dead one: if a working list exists but its heartbeat has gone
        stale, that process is gone and its jobs are fair game to recover.

        These keys are scoped per process and are managed for you — you never read
        or write them directly.
      MD

      DocsUI::Callout(:tip) do
        plain "Even with ReliableFetch enabled, keep the reaper running. It's the backstop for orphaned locks in edge cases — see "
        a(href: "/docs/orphaned-locks-and-recovery") { "Orphaned locks and recovery" }
        plain "."
      end
    end
  end
end

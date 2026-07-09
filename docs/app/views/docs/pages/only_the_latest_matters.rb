# frozen_string_literal: true

class Views::Docs::Pages::OnlyTheLatestMatters < DocsUI::Page
  title "Only the latest matters"
  eyebrow "Use cases"

  def lead = "When a newer job should overtake an older queued copy, use on_conflict: :replace so the latest payload wins."

  def content
    the_scenario
    the_worker
    what_replace_does
    replace_vs_log
    historical_caveat
  end

  private

  def the_scenario
    DocsUI::Section("The scenario", description: "A state snapshot where only the freshest version should run.") do
      md <<~'MD'
        You sync a document's state to an external system. A user edits the
        document, you enqueue a sync. They edit again a second later, you enqueue
        another. The queue now holds two jobs for the same document — but the
        first one carries **stale** state. Running it wastes work and, worse,
        risks writing an older snapshot on top of a newer one.

        What you want is simple: the newest enqueue should **replace** the one
        already waiting. The latest payload wins, the older copy never runs.
        That's exactly what `on_conflict: :replace` does.
      MD
    end
  end

  def the_worker
    DocsUI::Section("The worker") do
      md <<~'MD'
        Lock the job for its whole push-to-done lifecycle with `:until_executed`,
        and set `on_conflict: :replace` so a duplicate enqueue swaps out the
        waiting job instead of being dropped. Uniqueness keys on the
        `document_id` argument, so each document is tracked independently.
      MD

      DocsUI::Code(<<~RUBY)
        class SyncDocumentStateJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed,
                          on_conflict: :replace

          def perform(document_id)
            document = Document.find(document_id)
            ExternalSync.push(document.snapshot)
          end
        end
      RUBY

      md <<~'MD'
        Now a burst of edits to the same document collapses to a single sync that
        carries the most recent state:
      MD

      DocsUI::Code(<<~RUBY)
        SyncDocumentStateJob.perform_async(42)   # enqueued, lock acquired
        SyncDocumentStateJob.perform_async(42)   # replaces the first — newest wins
        SyncDocumentStateJob.perform_async(99)   # different document, independent
      RUBY
    end
  end

  def what_replace_does
    DocsUI::Section("What :replace does on a conflict") do
      md <<~'MD'
        When a second job arrives while the lock for that digest is held,
        `:replace` performs the swap in one motion:

        1. It **deletes** the job already sitting in the queue for that digest.
        2. It **releases** the lock that job was holding.
        3. It **enqueues** the new job and acquires the lock for it.

        The end state is a single queued job carrying the latest arguments —
        never two, and never the stale one. Because the worker uses
        `:until_executed`, the lock is held from enqueue right through to the end
        of `perform`, so the replacement window covers the entire time a
        duplicate could otherwise pile up.
      MD

      DocsUI::Callout(:tip) do
        plain "Uniqueness keys on worker class, queue, and args. Two edits to document 42 collide and replace; an edit to document 99 is a different digest and runs on its own."
      end
    end
  end

  def replace_vs_log
    DocsUI::Section("Contrast with :log — which copy survives?", description: "The difference is entirely about which job is kept.") do
      md <<~'MD'
        Both strategies leave you with exactly one job. They differ on *which*
        one — and that is the whole decision:

        | Strategy | On a duplicate | Which payload runs |
        |----------|----------------|--------------------|
        | `:replace` | Deletes the queued job and its lock, enqueues the new one | The **newest** — latest args win |
        | `:log` | Logs the conflict and discards the incoming job | The **original** — first args win |

        For a state snapshot, `:replace` is right: the freshest snapshot is the
        one worth sending. If instead you were debouncing an operation where the
        *first* request is authoritative and later ones are just noise, `:log`
        (the effective default) is the better fit — keep the original, drop the
        rest.
      MD
    end
  end

  def historical_caveat
    DocsUI::Section("A note on what gets replaced") do
      md <<~'MD'
        `:replace` targets the **queued** job — the duplicate that is still
        waiting to run. It finds the existing job for the digest, removes it, and
        puts the new one in its place. It does not reach into a job that has
        already started executing; once `perform` is underway, that run is left
        alone and the lock behaves according to your lock type.

        In practice this is what you want for a "latest wins" sync: you are
        racing enqueues, not interrupting work in flight. Pair `:replace` with
        `:until_executed` (as above) so the lock is held long enough for the
        replacement to matter.
      MD

      DocsUI::Callout(:note) do
        plain "For the full list of strategies and how to split client and server behavior, see "
        a(href: "/docs/conflict-resolution") { "Conflict resolution" }
        plain "."
      end
    end
  end
end

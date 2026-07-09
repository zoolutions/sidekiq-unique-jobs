# frozen_string_literal: true

class Views::Docs::Pages::WebUi < DocsUI::Page
  title "Web UI"
  eyebrow "Reference"

  def lead = "Add a Locks tab to the Sidekiq Web UI to browse, filter, and delete active locks."

  def content
    enabling
    what_it_shows
  end

  private

  def enabling
    DocsUI::Section("Enabling the Locks tab") do
      md <<~'MD'
        The gem ships a Sidekiq Web UI extension. Require it wherever you mount
        `Sidekiq::Web` — in `config/routes.rb`, right beside the mount — and a
        **Locks** tab appears in the Sidekiq dashboard:
      MD

      DocsUI::Code(<<~RUBY)
        # config/routes.rb
        require "sidekiq/web"
        require "sidekiq_unique_jobs/web"

        Rails.application.routes.draw do
          mount Sidekiq::Web, at: "/sidekiq"
        end
      RUBY

      md <<~'MD'
        The `require` must load before the mount so the extension can register
        its routes and the tab. Nothing else is needed — the tab reads the same
        two Redis keys every lock already uses.
      MD
    end
  end

  def what_it_shows
    DocsUI::Section("What the tab shows", description: "Browse, filter, and delete active locks.") do
      md <<~'MD'
        The Locks tab lists every active digest — the fingerprint that determines
        uniqueness (worker class, queue, and arguments). You can:

        - **Browse** every lock currently held in Redis.
        - **Filter** by digest to find a specific one.
        - **Delete** a lock by hand to release it immediately.

        Reach for it when a job won't enqueue and you suspect a **stuck digest**:
        open the tab, filter for the digest, and confirm whether a lock is still
        held. If a process crashed mid-job and left a lock behind, deleting it
        here clears the way for the next enqueue.
      MD

      DocsUI::Callout(:note) do
        plain "Deleting a lock is a manual override. You rarely need it — the reaper removes orphaned locks automatically. See "
        a(href: "/docs/orphaned-locks-and-recovery") { "Orphaned locks and recovery" }
        plain "."
      end
    end
  end
end

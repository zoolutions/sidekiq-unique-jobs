# frozen_string_literal: true

# docs-kit configuration — everything that makes this site look like
# "sidekiq-unique-jobs" rather than any other docs site. The shared chrome
# (Shell/Sidebar/ThemeSwitcher/Code/Page) comes from the gem; only this config
# differs per site. The `themes` MUST match the @plugin "daisyui" { themes: ... }
# block in app/assets/stylesheets/application.tailwind.css, or the switcher
# offers a theme the compiled CSS never generated.
Rails.application.config.to_prepare do
  DocsKit.configure do |c|
    c.brand        = "sidekiq-unique-jobs"
    c.title_suffix = "sidekiq-unique-jobs"

    # The one-line summary agents read first in /llms.txt (the llmstxt.org
    # blockquote under the H1).
    c.tagline = "Redis-backed uniqueness for Sidekiq jobs — prevent duplicate " \
                "enqueues and concurrent execution with configurable lock types, " \
                "conflict strategies, and orphan recovery. Two Redis keys per lock."

    c.themes = %w[dark light synthwave retro cyberpunk dracula night nord sunset]

    # The version badge in the sidebar header tracks the documented gem. A lambda
    # (not a String) so it re-reads SidekiqUniqueJobs::VERSION on every reload —
    # the path-gem is required as "sidekiq_unique_jobs/version" (Gemfile), so only
    # the constant is loaded; the gem's Sidekiq/Redis stack never boots here.
    c.version_badge = -> { "v#{SidekiqUniqueJobs::VERSION}" }

    # Code blocks: a light base with a dark override, so the highlight stays
    # readable when the switcher lands on a dark daisyUI theme. CSS-only scoping
    # ([data-theme=X]) — no JS, no flash.
    c.code_theme      = "Rouge::Themes::Github"  # light themes
    c.code_theme_dark = "Rouge::Themes::Monokai" # dark themes

    # Repo + rubygems links in the topbar, rendered with the shipped brand marks.
    c.topbar_links = [
      { href: "https://github.com/mhenrixon/sidekiq-unique-jobs", label: "GitHub", icon: :github },
      { href: "https://rubygems.org/gems/sidekiq-unique-jobs", label: "RubyGems", icon: :rubygems }
    ]

    # SEO + social sharing. docs-kit emits the full <head> (description, Open
    # Graph, Twitter Card, canonical, favicon, theme-color) from these knobs.
    # og_image resolves through THIS site's asset pipeline (app/assets/images/) to
    # the digested /assets URL — regenerate the card with `bin/rails docs_kit:og`.
    c.seo.description  = "Redis-backed uniqueness for Sidekiq jobs. Prevent " \
                         "duplicate enqueues and concurrent execution with " \
                         "configurable lock types (until_executed, while_executing, " \
                         "until_expired and more), five conflict strategies, and " \
                         "automatic orphan-lock recovery."
    c.seo.site_url     = "https://sidekiq-unique-jobs.zoolutions.llc"
    c.seo.og_image     = "og/og.png"
    c.seo.og_type      = "website"
    c.seo.twitter_card = "summary_large_image"
    c.seo.twitter_site = "@mhenrixon"
    c.seo.locale       = "en_US"
    c.seo.theme_color  = "#1d232a" # daisyUI dark base-100 (themes.first)
    # favicon href is used verbatim (not through the asset pipeline), so it's a
    # public/ path served at a stable root URL.
    c.seo.favicon      = "/icon.svg"

    # The home page ("/") — a marketing hero + feature grid, all from config.
    # Highlight a run in the title with **double asterisks** (primary color).
    c.landing.eyebrow = "Sidekiq middleware"
    c.landing.title   = "Duplicate jobs, **prevented**."
    c.landing.lead    = "sidekiq-unique-jobs stops the same job from being " \
                        "enqueued twice or run concurrently. Pick a lock type, " \
                        "pick what happens on a conflict, and let Redis keep " \
                        "your jobs unique."
    c.landing.install = { code: 'gem "sidekiq-unique-jobs", "~> 9.0"', filename: "Gemfile", lexer: :ruby }
    c.landing.ctas = [
      { label: "Get started", href: "/docs/overview", style: :primary },
      { label: "GitHub", href: "https://github.com/mhenrixon/sidekiq-unique-jobs", style: :ghost, icon: :github }
    ]
    c.landing.features = [
      { icon: "lock", title: "Five lock types",
        body: "From debouncing enqueues to serializing execution — choose the " \
              "lock that matches the guarantee you need." },
      { icon: "git-branch", title: "Conflict strategies",
        body: "Log, raise, reject, replace, or reschedule when a duplicate " \
              "shows up. Different rules for enqueue and execute." },
      { icon: "database", title: "Two Redis keys per lock",
        body: "v9 is a ground-up rewrite: a LOCKED hash and a global digests " \
              "sorted set. Less memory, fewer moving parts." },
      { icon: "recycle", title: "Orphan recovery",
        body: "A reaper cleans up locks left behind by crashed processes, so a " \
              "hard kill never wedges a digest forever." },
      { icon: "activity", title: "Observable",
        body: "Reflection hooks fire on every lock event — wire them into your " \
              "metrics and logs without patching the gem." },
      { icon: "layout-dashboard", title: "Web UI",
        body: "A Locks tab in the Sidekiq Web UI to browse, filter, and delete " \
              "locks when you need to see what's held." }
    ]

    # The sidebar nav derives from the registry — one heading → one registry.
    # Each registry's authored pages become NavItems automatically (an unwritten
    # page is skipped, so no dead links); the page `group:` values render as the
    # collapsible sub-groups. This also feeds the AI surfaces (/llms.txt,
    # /llms-full.txt, search, MCP) with zero extra code.
    c.nav_registries = { "Docs" => Doc }
  end
end

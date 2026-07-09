# frozen_string_literal: true

class Views::Docs::Pages::ConfigurationReference < DocsUI::Page
  title "Configuration reference"
  eyebrow "Reference"

  def lead = "Every global option you can set in a SidekiqUniqueJobs.configure block, grouped by concern."

  def content
    configure_block
    render_groups
  end

  private

  def configure_block
    DocsUI::Section("The configure block", description: "Set global defaults once, at boot.") do
      md <<~'MD'
        Global configuration lives in a `SidekiqUniqueJobs.configure` block —
        typically in your Sidekiq initializer, alongside the middleware. Every
        value here is a **default**: a worker's own `sidekiq_options` always wins
        over the global setting. For the per-worker keys, see
        [Worker options](/docs/worker-options).
      MD

      DocsUI::Code(<<~RUBY)
        # config/initializers/sidekiq.rb
        SidekiqUniqueJobs.configure do |config|
          config.enabled          = true
          config.lock_ttl         = nil     # locks don't expire on their own
          config.lock_timeout     = 0       # fail fast when a lock is held
          config.lock_prefix      = "uniquejobs"
          config.on_conflict      = nil     # defer to each worker's on_conflict
          config.reaper           = :ruby   # safe orphan cleanup
          config.reaper_count     = 1000
          config.reaper_interval  = 600
          config.digest_algorithm = :legacy
        end
      RUBY

      md <<~'MD'
        The tables below list every option, its type, its default, and what it
        controls. They are generated from the gem's real config struct and
        drift-tested against it, so a renamed or added option fails the build
        until this reference is updated.
      MD
    end
  end

  def render_groups
    ConfigReference::GROUPS.each do |group_name, rows|
      DocsUI::Section(group_name) do
        DocsUI::PropTable(rows.map { |o| [ o[:name], o[:type], o[:default], o[:desc] ] })
      end
    end
  end
end

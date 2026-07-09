# frozen_string_literal: true

class Views::Docs::Pages::Installation < DocsUI::Page
  title "Installation"
  eyebrow "Getting started"

  def lead = "Add the gem, then wire the middleware into your Sidekiq initializer — without it, jobs silently won't be unique."

  def content
    add_the_gem
    requirements
    wire_the_middleware
    ordering
    next_steps
  end

  private

  def add_the_gem
    DocsUI::Section("Add the gem") do
      md <<~'MD'
        Add sidekiq-unique-jobs to your `Gemfile`:
      MD

      DocsUI::Code(<<~RUBY)
        gem "sidekiq-unique-jobs", "~> 9.0"
      RUBY

      md <<~'MD'
        Then install it:
      MD

      DocsUI::Code(<<~BASH, lexer: :bash)
        bundle install
      BASH
    end
  end

  def requirements
    DocsUI::Section("Requirements") do
      md <<~'MD'
        v9 is a ground-up rewrite that targets modern runtimes. Redis 6.2 is the
        floor because the lock scripts rely on `LMOVE`.
      MD

      DocsUI::PropTable([
        [ "Ruby", "runtime", ">= 3.2", "Earlier rubies are not supported." ],
        [ "Sidekiq", "gem", ">= 8.0", "v9 is Sidekiq 8+ only." ],
        [ "Redis", "server", ">= 6.2", "Required for the atomic LMOVE used by the lock scripts." ]
      ])
    end
  end

  def wire_the_middleware
    DocsUI::Section("Wire the middleware", description: "The one step that actually turns uniqueness on.") do
      md <<~'MD'
        Uniqueness is enforced by two pieces of Sidekiq middleware: a **client**
        middleware that runs when a job is enqueued, and a **server** middleware
        that runs when a job executes. Add both in
        `config/initializers/sidekiq.rb`, and call
        `SidekiqUniqueJobs::Server.configure` on the server so the reaper and
        other server-side machinery start up.
      MD

      DocsUI::Code(<<~RUBY)
        # config/initializers/sidekiq.rb
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add SidekiqUniqueJobs::Middleware::Client
          end
        end

        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add SidekiqUniqueJobs::Middleware::Client
          end
          config.server_middleware do |chain|
            chain.add SidekiqUniqueJobs::Middleware::Server
          end
          SidekiqUniqueJobs::Server.configure(config)
        end
      RUBY

      md <<~'MD'
        The client middleware is added in **both** blocks on purpose: your web
        process enqueues jobs, but so do your Sidekiq workers (a job that calls
        `perform_async` on another job). Registering it on the server as well
        keeps those enqueues unique too.
      MD

      DocsUI::Callout(:warning) do
        plain "Since v7 the middleware is NOT auto-loaded. If you skip this step, everything installs and boots without error — but no lock is ever taken and your jobs will silently run as duplicates. Adding a `lock:` option to a worker does nothing until the middleware is wired up here."
      end
    end
  end

  def ordering
    DocsUI::Section("Middleware ordering") do
      md <<~'MD'
        When you run sidekiq-unique-jobs alongside other middleware gems
        (apartment-sidekiq, sidekiq-global_id, sidekiq-status, ...), order
        matters. As a rule of thumb, this gem's middleware should run **last** on
        both the client and the server chain, so the digest is computed after any
        other gem has finished rewriting the job payload.

        Because `chain.add` appends to the end of the chain, adding these entries
        after your other middleware is usually enough. If you need to be explicit,
        Sidekiq's `chain.insert_after` / `chain.insert_before` let you place them
        precisely.
      MD

      DocsUI::Callout(:note) do
        plain "The README documents the exact ordering for specific gem combinations — start there if uniqueness behaves oddly next to another middleware gem."
      end
    end
  end

  def next_steps
    DocsUI::Section("Next steps") do
      md <<~'MD'
        The middleware is wired up — now make a job unique. Head to
        [Quick start](/docs/quick-start) to write your first unique worker.
      MD
    end
  end
end

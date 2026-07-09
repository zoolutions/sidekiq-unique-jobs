# frozen_string_literal: true

class Views::Docs::Pages::TestingUniqueJobs < DocsUI::Page
  title "Testing unique jobs"
  eyebrow "Testing"

  def lead = "In your own test suite, disable uniqueness and trust the gem — reach for real Redis only when you're testing lock behavior on purpose."

  def content
    disable_by_default
    testing_lock_behavior
    scoped_config
    the_rule
  end

  private

  def disable_by_default
    DocsUI::Section("Disable uniqueness in your tests", description: "Turn the gem off so it never fights your test setup.") do
      md <<~'MD'
        The uniqueness machinery is there to protect **production**, not to be
        re-exercised by every app that installs the gem. In your own suite it
        mostly gets in the way: a job that was locked in one example can silently
        refuse to enqueue in the next, and your test failures start pointing at
        Redis state instead of your code.

        The fix is one line. Turn uniqueness off globally, once, in your test
        boot:
      MD

      DocsUI::Code(<<~RUBY)
        # spec/rails_helper.rb (or spec/spec_helper.rb)
        require "sidekiq_unique_jobs"

        RSpec.configure do |config|
          config.before(:suite) do
            SidekiqUniqueJobs.config.enabled = false
          end
        end
      RUBY

      md <<~'MD'
        With `enabled = false`, the client and server middleware become no-ops:
        jobs enqueue and run exactly as they would without the gem, and no locks
        are written to Redis. Your tests assert on *your* behavior — that a job
        was enqueued, that it did the right thing — without any uniqueness in the
        picture.
      MD

      DocsUI::Callout(:note) do
        plain "This flips the global "
        a(href: "/docs/configuration-reference") { "configuration" }
        plain ", so set it once for the whole suite rather than per-example."
      end
    end
  end

  def testing_lock_behavior
    DocsUI::Section("When you do need to test locking", description: "Use real Redis, real testing modes, and clean state between examples.") do
      md <<~'MD'
        Occasionally you *are* testing the lock itself — a custom `lock_args`
        method, or that a specific worker is configured for uniqueness at all.
        When you do, two things matter: use **real Redis** (the lock lives in Lua
        scripts, so mocks can't reproduce it), and **clear it between examples**
        so one test never inherits another's locks.

        Enable uniqueness for just those examples and flush Redis around each one:
      MD

      DocsUI::Code(<<~RUBY)
        RSpec.describe "locking behavior" do
          before do
            SidekiqUniqueJobs.config.enabled = true
            SidekiqUniqueJobs.redis(&:flushdb)
          end

          after do
            SidekiqUniqueJobs.config.enabled = false
          end
        end
      RUBY

      md <<~'MD'
        ### Testing modes

        Sidekiq's testing modes change *when* jobs run, and that changes what
        uniqueness you can observe:

        - **`Sidekiq::Testing.inline!`** runs a job the moment it's enqueued, on
          the same thread — with the client and server middleware both firing, so
          uniqueness is fully enforced. Use it to test end-to-end lock behavior.
        - **`Sidekiq::Testing.disable!`** pushes jobs to real Redis without
          running them, so only the *client* (enqueue-time) lock applies. Use it
          to test that a duplicate enqueue is prevented while nothing is executing.

        A worker that locks from enqueue until execution completes:
      MD

      DocsUI::Code(<<~RUBY)
        class RefreshReportJob
          include Sidekiq::Job

          sidekiq_options lock: :until_executed

          def perform(report_id)
            Report.find(report_id).refresh!
          end
        end
      RUBY

      md <<~'MD'
        Testing that the client lock blocks a duplicate enqueue. Because
        `disable!` pushes to **real Redis**, `RefreshReportJob.jobs` (the fake
        in-memory array) stays empty — assert on the real queue instead, and
        clear it around the example:
      MD

      DocsUI::Code(<<~RUBY)
        RSpec.describe RefreshReportJob do
          before do
            SidekiqUniqueJobs.config.enabled = true
            SidekiqUniqueJobs.redis(&:flushdb)
            Sidekiq::Queue.new("default").clear
            Sidekiq::Testing.disable!
          end

          after do
            Sidekiq::Queue.new("default").clear
            SidekiqUniqueJobs.config.enabled = false
          end

          it "enqueues only one job per report" do
            described_class.perform_async(42)
            described_class.perform_async(42)

            expect(Sidekiq::Queue.new("default").size).to eq(1)
          end
        end
      RUBY

      md <<~'MD'
        Testing that the lock is held across a full inline run:
      MD

      DocsUI::Code(<<~RUBY)
        RSpec.describe RefreshReportJob do
          before do
            SidekiqUniqueJobs.config.enabled = true
            SidekiqUniqueJobs.redis(&:flushdb)
            Sidekiq::Testing.inline!
          end

          after { SidekiqUniqueJobs.config.enabled = false }

          it "runs the job and releases the lock afterward" do
            expect(Report).to receive(:find).with(42).and_call_original

            described_class.perform_async(42)

            expect(SidekiqUniqueJobs::Digests.new.count).to eq(0)
          end
        end
      RUBY

      DocsUI::Callout(:warning) do
        plain "Never mock Redis for these tests. The lock lives entirely in Lua scripts against a real server — a stubbed client won't reproduce acquire, expiry, or release, so a green test would prove nothing."
      end
    end
  end

  def scoped_config
    DocsUI::Section("Overriding config for a single block", description: "use_config restores everything when the block returns.") do
      md <<~'MD'
        When one example needs a different setting — a shorter `lock_ttl`, a
        specific `digest_algorithm`, uniqueness switched on — reach for
        `SidekiqUniqueJobs.use_config`. It applies the overrides for the duration
        of the block and restores the previous values on the way out, even if the
        block raises, so no other test inherits your change.
      MD

      DocsUI::Code(<<~RUBY)
        RSpec.describe RefreshReportJob do
          before do
            SidekiqUniqueJobs.redis(&:flushdb)
            Sidekiq::Queue.new("default").clear
          end

          after { Sidekiq::Queue.new("default").clear }

          it "enforces uniqueness only inside the block" do
            SidekiqUniqueJobs.use_config(enabled: true) do
              Sidekiq::Testing.disable!

              described_class.perform_async(42)
              described_class.perform_async(42)

              # disable! pushes to real Redis, so assert on the real queue.
              expect(Sidekiq::Queue.new("default").size).to eq(1)
            end
            # enabled is back to whatever it was before the block.
          end
        end
      RUBY

      md <<~'MD'
        Any config key works the same way — pass as many as you need:
      MD

      DocsUI::Code(<<~RUBY)
        SidekiqUniqueJobs.use_config(enabled: true, lock_ttl: 5, digest_algorithm: :modern) do
          # ... assertions that depend on these settings ...
        end
      RUBY

      DocsUI::Callout(:tip) do
        plain "use_config is the surgical alternative to toggling globals in before/after hooks — prefer it when only one example needs the override."
      end
    end
  end

  def the_rule
    DocsUI::Section("The one rule to remember") do
      md <<~'MD'
        The gem ships with a thorough suite that covers every lock type, every
        conflict strategy, and the reaper — end to end, against real Redis. You
        don't need to reproduce any of that in your application. Testing "does
        `:until_executed` actually prevent a duplicate?" is testing the gem, not
        your app.

        - **In unit tests:** keep `SidekiqUniqueJobs.config.enabled = false`.
        - **In the rare lock-behavior test:** enable it, use real Redis, flush
          between examples, and pick the testing mode that matches the lock phase
          you're checking.
      MD

      DocsUI::Callout(:tip) do
        plain "Trust the gem's suite. Disable uniqueness in your unit tests, and only turn it on for the handful of examples that are genuinely about the lock."
      end
    end
  end
end

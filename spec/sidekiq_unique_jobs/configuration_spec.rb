# frozen_string_literal: true

# rubocop:disable-next RSpec/SpecFilePathFormat
RSpec.describe SidekiqUniqueJobs do
  describe "define custom lock strategies" do
    subject(:middleware_call) do
      SidekiqUniqueJobs::Middleware::Client.new.call(job_class, item, queue) do
        true
      end
    end

    let(:foobar_job) do
      Class.new(MyJob) do
        sidekiq_options lock: :foobar,
          queue: :customqueue,
          on_conflict: :raise
      end
    end

    let(:custom_lock) do
      Class.new(SidekiqUniqueJobs::Lock::BaseLock) do
        # rubocop:disable-next Naming/PredicateMethod
        def lock
          true
        end
      end
    end

    let(:queue)     { :customqueue }
    let(:lock_type) { :foobar }
    let(:digest)    { "uniquejobs:1234567890" }
    let(:jid)       { "randomjid" }
    let(:ttl)       { nil }
    let(:item) do
      {
        "lock_digest" => digest,
        "jid" => jid,
        "lock_expiration" => ttl,
        "lock" => lock_type,
      }
    end
    let(:job_class) { foobar_job }

    context "when the lock is not defined" do
      it "raises SidekiqUniqueJobs::UnknownLock" do
        expect { middleware_call }.to raise_exception(
          SidekiqUniqueJobs::UnknownLock, /No implementation for `lock: :foobar`/
        )
      end
    end

    context "when the lock is defined" do
      let(:custom_config) do
        SidekiqUniqueJobs::Config.default.tap do |cfg|
          cfg.add_lock :foobar, custom_lock
        end
      end

      before do
        allow(described_class).to receive(:config).and_return(custom_config)
      end

      it "returns the block given" do
        expect(middleware_call).to be(true)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe SidekiqUniqueJobs::Logging do
  let(:logger)  { SidekiqUniqueJobs.logger }
  let(:message) { "A log message" }
  let(:level)   { nil }
  let(:worker)  { "JustAWorker" }
  let(:queue)   { "testqueue" }
  let(:args)    { [{ foo: "bar" }] }
  let(:jid)     { "jobid" }
  let(:digest)  { "digestable" }
  let(:item) do
    { "class" => worker,
      "queue" => queue,
      "args" => args,
      "jid" => jid,
      "lock_digest" => digest }
  end

  before do
    allow(logger).to receive(level)
  end

  include described_class

  describe "#log_debug" do
    let(:level) { :debug }

    it "delegates to logger.debug" do
      expect(log_debug(message, item)).to be_nil
      expect(logger).to have_received(level).with(
        a_string_starting_with(message)
          .and(ending_with("(queue=#{queue} class=#{worker} jid=#{jid} lock_digest=#{digest})")),
      )
    end

    context "when logging is disabled" do
      it "logs nothing" do
        SidekiqUniqueJobs.use_config(logger_enabled: false) do
          log_debug(message, item)
          expect(logger).not_to have_received(level)
        end
      end
    end
  end

  describe "#log_info" do
    let(:level) { :info }

    it "delegates to logger.info" do
      expect(log_info(message, item)).to be_nil
      expect(logger).to have_received(level).with(
        a_string_starting_with(message)
          .and(ending_with("(queue=#{queue} class=#{worker} jid=#{jid} lock_digest=#{digest})")),
      )
    end

    context "when logging is disabled" do
      it "logs nothing" do
        SidekiqUniqueJobs.use_config(logger_enabled: false) do
          log_info(message, item)
          expect(logger).not_to have_received(level)
        end
      end
    end
  end

  describe "#log_warn" do
    let(:level) { :warn }

    it "delegates to logger.warn" do
      expect(log_warn(message, item)).to be_nil
      expect(logger).to have_received(level).with(
        a_string_starting_with(message)
          .and(ending_with("(queue=#{queue} class=#{worker} jid=#{jid} lock_digest=#{digest})")),
      )
    end

    context "when logging is disabled" do
      it "logs nothing" do
        SidekiqUniqueJobs.use_config(logger_enabled: false) do
          log_warn(message, item)
          expect(logger).not_to have_received(level)
        end
      end
    end
  end

  describe "#log_error" do
    let(:level) { :error }

    it "delegates to logger.error" do
      expect(log_error(message, item)).to be_nil
      expect(logger).to have_received(level).with(
        a_string_starting_with(message)
          .and(ending_with("(queue=#{queue} class=#{worker} jid=#{jid} lock_digest=#{digest})")),
      )
    end

    context "when logging is disabled" do
      it "logs nothing" do
        SidekiqUniqueJobs.use_config(logger_enabled: false) do
          log_error(message, item)
          expect(logger).not_to have_received(level)
        end
      end
    end
  end

  describe "#log_fatal" do
    let(:level) { :fatal }

    it "delegates to logger.fatal" do
      expect(log_fatal(message, item)).to be_nil
      expect(logger).to have_received(level).with(
        a_string_starting_with(message)
          .and(ending_with("(queue=#{queue} class=#{worker} jid=#{jid} lock_digest=#{digest})")),
      )
    end

    context "when logging is disabled" do
      it "logs nothing" do
        SidekiqUniqueJobs.use_config(logger_enabled: false) do
          log_fatal(message, item)
          expect(logger).not_to have_received(level)
        end
      end
    end
  end

  describe "#logging_context" do
    let(:level)   { :error }

    it { expect { logging_context }.to raise_error(NotImplementedError) }
  end

  describe "#with_configured_loggers_context" do
    let(:level) { :warn }

    context "when Sidekiq::Logging is defined" do
      let(:logging_context) { { "hey" => "ho" } }

      before do
        hide_const("Sidekiq::Context")
        stub_const("Sidekiq::Logging", Class.new do
          def self.with_context(_msg)
            yield
          end
        end)

        allow(logger).to receive(:respond_to?).with(:with_context).and_return(false)
        allow(Sidekiq::Logging).to receive(:with_context).and_call_original
      end

      it "sets up a logging context" do
        with_configured_loggers_context do
          log_warn("TOODELOO")
        end

        expect(logger).to have_received(:warn).with("TOODELOO")
      end
    end

    context "when logger does not support context" do
      let(:logger)          { Logger.new(File::NULL) }
      let(:logging_context) { { "fuu" => "bar" } }

      before do
        allow(logger).to receive(:respond_to?).with(:with_context).and_return(false)
        hide_const("Sidekiq::Logging")
        hide_const("Sidekiq::Context")

        allow(self).to receive(:no_sidekiq_context_method).and_call_original
      end

      it "logs a warning" do
        with_configured_loggers_context {}

        expect(logger).to have_received(:warn).with(
          "Don't know how to setup the logging context. Please open a feature request: " \
          "https://github.com/zoolutions/sidekiq-unique-jobs/issues/new?template=feature_request.md",
        )
      end
    end

    context "when Sidekiq::Context is defined" do
      let(:logging_context) { { "sheet" => "ya" } }

      before do
        stub_const("Sidekiq::Context", Class.new do
          def self.with(_hash)
            yield
          end
        end)

        allow(Sidekiq::Context).to receive(:with).and_call_original
      end

      it "sets up a logging context" do
        with_configured_loggers_context do
          log_warn("TOODELEE")
        end

        expect(logger).to have_received(:warn).with("TOODELEE")
      end
    end
  end
end

# frozen_string_literal: true

# rubocop:disable-next RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe SidekiqUniqueJobs::Middleware::Server, "lock: :until_and_while_executing" do
  let(:server) { described_class.new }

  let(:jid_one)      { "jid one" }
  let(:jid_two)      { "jid two" }
  let(:lock_timeout) { nil }
  let(:sleepy_time)  { 0 }
  let(:job_class)    { UntilAndWhileExecutingJob }
  let(:unique)       { :until_and_while_executing }
  let(:queue)        { :another_queue }
  let(:args)         { [sleepy_time] }
  let(:callback)     { -> {} }
  let(:item_one) do
    { "jid" => jid_one,
      "class" => job_class.to_s,
      "queue" => queue,
      "lock" => unique,
      "args" => args,
      "lock_timeout" => lock_timeout }
  end
  let(:item_two) do
    item_one.merge("jid" => jid_two)
  end

  let(:key)     { SidekiqUniqueJobs::Key.new("uniquejobs:f07093737839f88af8593c945143574d") }
  let(:run_key) { SidekiqUniqueJobs::Key.new("uniquejobs:f07093737839f88af8593c945143574d:RUN") }

  context "when item_one is locked" do
    before do
      push_item(item_one)
    end

    context "with a lock_timeout of 0" do
      let(:lock_timeout) { nil }

      context "when processing takes 0 seconds" do
        it "item_one can be executed by server" do
          set = false
          server.call(job_class, item_one, queue) { set = true }
          expect(set).to be(true)
        end
      end
    end
  end
end

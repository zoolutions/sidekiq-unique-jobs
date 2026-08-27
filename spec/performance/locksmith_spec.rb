# frozen_string_literal: true

RSpec.describe SidekiqUniqueJobs::Locksmith, :perf do
  let(:locksmith_one) { described_class.new(item_one) }
  let(:locksmith_two) { described_class.new(item_two) }

  let(:jid_one)      { "maaaahjid" }
  let(:jid_two)      { "jidmayhem" }
  let(:lock_ttl)     { nil }
  let(:lock_type)    { "until_executed" }
  let(:digest)       { "uniquejobs:randomvalue" }
  let(:key)          { SidekiqUniqueJobs::Key.new(digest) }
  let(:lock)         { SidekiqUniqueJobs::Lock.new(key) }
  let(:lock_timeout) { 0 }
  let(:lock_limit)   { 1 }
  let(:item_one) do
    {
      "jid" => jid_one,
      "lock_digest" => digest,
      "lock_ttl" => lock_ttl,
      "lock" => lock_type,
      "lock_timeout" => lock_timeout,
      "lock_limit" => lock_limit,
    }
  end
  let(:item_two) { item_one.merge("jid" => jid_two) }

  context "when already locked" do
    before { locksmith_one.lock }

    after { locksmith_one.delete! }

    it "locks in under 2 ms" do
      expect { locksmith_two.lock {} }.to perform_under(2).ms
    end
  end

  it "locks in under 2 ms" do
    expect { locksmith_one.lock {} }.to perform_under(2).ms
  end

  it "unlocks in under 1 ms" do
    locksmith_one.lock

    expect { locksmith_one.unlock }.to perform_under(1).ms
  end
end

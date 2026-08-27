# frozen_string_literal: true

RSpec.describe SidekiqUniqueJobs::Locksmith do
  let(:locksmith_one) { described_class.new(item_one) }
  let(:locksmith_two) { described_class.new(item_two) }

  let(:jid_one)      { "maaaahjid" }
  let(:jid_two)      { "jidmayhem" }
  let(:lock_ttl)     { nil }
  let(:lock_type)    { "until_executed" }
  let(:digest)       { "uniquejobs:randomvalue" }
  let(:key)          { SidekiqUniqueJobs::Key.new(digest) }
  let(:lock_timeout) { 0 }
  let(:lock_limit)   { 1 }
  let(:queue)        { "default" }
  let(:worker)       { "UntilExecutedJob" }
  let(:lock_args)    { ["abc"] }
  let(:item_one) do
    {
      "class" => "UntilExecutedJob",
      "jid" => jid_one,
      "lock" => lock_type,
      "lock_args" => lock_args,
      "lock_digest" => digest,
      "lock_limit" => lock_limit,
      "lock_timeout" => lock_timeout,
      "lock_ttl" => lock_ttl,
      "queue" => queue,
    }
  end
  let(:key_one)  { locksmith_one.key }
  let(:key_two)  { locksmith_two.key }
  let(:item_two) { item_one.merge("jid" => jid_two) }

  describe "#to_s" do
    it "outputs a helpful string" do
      expect(locksmith_one.to_s).to eq(
        "Locksmith##{locksmith_one.object_id}" \
        "(digest=#{digest} job_id=#{jid_one} locked=false)",
      )
    end
  end

  describe "#inspect" do
    it "outputs a helpful string" do
      expect(locksmith_one.inspect).to eq(
        "Locksmith##{locksmith_one.object_id}" \
        "(digest=#{digest} job_id=#{jid_one} locked=false)",
      )
    end
  end

  describe "#==" do
    it "is true when locksmiths are comparable" do
      expect(locksmith_one == locksmith_one.dup).to be(true)
    end

    it "is false when locksmiths are incomparable" do
      expect(locksmith_one == locksmith_two).to be(false)
    end
  end

  shared_examples_for "a lock" do
    it "is unlocked from the start" do
      expect(locksmith_one).not_to be_locked
    end

    it "locks and unlocks" do
      locksmith_one.lock
      expect(locksmith_one).to be_locked
      locksmith_one.unlock
      expect(locksmith_one).not_to be_locked if lock_ttl.nil?
    end

    it "does not lock twice as a mutex" do
      expect(locksmith_one.lock).to be_truthy
      expect(locksmith_two.lock).to be_falsey
    end

    it "executes the given code block" do
      code_executed = false
      locksmith_one.execute do
        code_executed = true
      end
      expect(code_executed).to be(true)
    end

    it "returns the value of the block if block-style locking is used" do
      block_value = locksmith_one.execute do
        42
      end

      expect(block_value).to eq(42)
    end

    it "disappears without a trace when calling delete!" do
      locksmith_one.lock
      locksmith_one.delete!

      expect(locksmith_one).not_to be_locked
    end

    context "when lock_timeout is zero" do
      let(:lock_timeout) { 0 }

      it "does not block" do
        did_we_get_in = false

        locksmith_one.execute do
          locksmith_two.execute do
            did_we_get_in = true
          end
        end

        expect(did_we_get_in).to be false
      end

      it "is locked" do
        locksmith_one.execute do
          expect(locksmith_one).to be_locked
        end

        expect(locksmith_one).not_to be_locked if lock_ttl.nil?
      end
    end
  end

  context "with lock_ttl" do
    let(:lock_ttl)  { 1 }
    let(:lock_type) { :while_executing }

    it_behaves_like "a lock"

    context "when lock_type is until_expired" do
      let(:lock_type) { :until_expired }

      it "prevents other processes from locking" do
        locksmith_one.lock

        sleep 0.1

        expect(locksmith_two.lock).to be_falsey
      end

      it "expires the expected keys" do
        locksmith_one.lock
        locksmith_one.unlock

        expect(locksmith_one).to be_locked
      end
    end

    context "when lock_type is anything else than until_expired" do
      let(:lock_type) { :until_executed }

      it "expires the expected keys" do
        locksmith_one.lock
        expect(locksmith_one).to be_locked
        locksmith_one.unlock
        expect(locksmith_one).not_to be_locked
        expect(locksmith_one.delete).to be_nil

        expect(locksmith_one).not_to be_locked
      end
    end

    it "deletes the expected keys" do
      locksmith_one.lock
      expect(locksmith_one).to be_locked
      locksmith_one.delete!
      expect(locksmith_one).not_to be_locked
    end

    it "expires keys" do
      locksmith_one.lock
      keys = unique_keys
      expect(unique_keys).not_to include(keys)
    end

    it "expires keys after unlocking" do
      locksmith_one.execute do
        # noop
      end
      keys = unique_keys
      expect(unique_keys).not_to include(keys)
    end
  end

  context "when lock_timeout is 1" do
    let(:lock_timeout) { 1 }

    it "blocks other locks" do
      did_we_get_in = false

      locksmith_one.execute do
        locksmith_two.execute do
          did_we_get_in = true
        end
      end

      expect(did_we_get_in).to be false
    end
  end

  it "records locked metric when lock succeeds" do
    locksmith_one.lock

    results = SidekiqUniqueJobs::LockMetrics.query(minutes: 1)
    expect(results["until_executed|locked"]).to eq(1)
  end

  it "records lock_failed metric when lock fails" do
    locksmith_one.lock
    locksmith_two.lock

    results = SidekiqUniqueJobs::LockMetrics.query(minutes: 1)
    expect(results["until_executed|lock_failed"]).to eq(1)
  end

  it "records unlocked metric on unlock" do
    locksmith_one.lock
    locksmith_one.unlock

    results = SidekiqUniqueJobs::LockMetrics.query(minutes: 1)
    expect(results["until_executed|unlocked"]).to eq(1)
  end

  describe "lock acquisition" do
    it "acquires the lock" do
      expect(locksmith_one.lock).to eq(jid_one)
      expect(locksmith_one).to be_locked
    end

    it "prevents concurrent locks (mutex behavior)" do
      locksmith_one.lock
      expect(locksmith_two.lock).to be_falsey
    end

    it "is idempotent for the same job_id" do
      locksmith_one.lock
      expect(locksmith_one).to be_locked

      expect(locksmith_one.lock).to eq(jid_one)
      expect(locksmith_one).to be_locked
    end

    it "stores metadata in the LOCKED hash" do
      locksmith_one.lock

      redis do |conn|
        metadata_json = conn.call("HGET", key.locked, jid_one)
        metadata = JSON.parse(metadata_json)

        expect(metadata).to include(
          "worker" => worker,
          "queue" => queue,
          "type" => lock_type.to_s,
        )
      end
    end

    context "with lock_ttl" do
      let(:lock_ttl) { 50_000 }

      it "acquires the lock with TTL" do
        expect(locksmith_one.lock).to eq(jid_one)
        expect(locksmith_one).to be_locked
      end
    end

    context "with lock_ttl nil (no expiration)" do
      let(:lock_ttl) { nil }

      it "acquires and releases the lock" do
        locksmith_one.lock
        expect(locksmith_one).to be_locked
        locksmith_one.unlock
        expect(locksmith_one).not_to be_locked
      end
    end

    context "with lock_limit > 1" do
      let(:lock_limit) { 3 }

      it "allows multiple concurrent locks within the limit" do
        locksmith_one.lock
        expect(locksmith_two.lock).to be_truthy
      end
    end
  end
end

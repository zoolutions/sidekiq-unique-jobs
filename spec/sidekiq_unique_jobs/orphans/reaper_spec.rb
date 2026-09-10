# frozen_string_literal: true

RSpec.describe SidekiqUniqueJobs::Orphans::Reaper do
  around do |example|
    SidekiqUniqueJobs.use_config(reaper_timeout: 10, reaper_count: 1_000) do
      example.run
    end
  end

  let(:digests_key) { "uniquejobs:digests" }
  let(:old_score) { (Time.now.to_f - 60).to_s }

  def create_lock(digest, jid)
    redis do |conn|
      conn.call("ZADD", digests_key, old_score, digest)
      conn.call("HSET", "#{digest}:LOCKED", jid, '{"type":"until_executed"}')
    end
  end

  describe ".call" do
    it "returns 0 when there are no digests" do
      expect(described_class.call).to eq(0)
    end

    it "removes digests with no LOCKED hash" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      redis { |conn| conn.call("ZADD", digests_key, old_score, digest) }

      expect(described_class.call).to eq(1)

      redis do |conn|
        expect(conn.call("ZSCORE", digests_key, digest)).to be_nil
      end
    end

    it "removes orphaned locks not found in any Sidekiq set" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      create_lock(digest, SecureRandom.hex(12))

      expect(described_class.call).to eq(1)

      redis do |conn|
        expect(conn.call("EXISTS", "#{digest}:LOCKED")).to eq(0)
        expect(conn.call("ZSCORE", digests_key, digest)).to be_nil
      end
    end

    it "removes multiple orphaned locks in one run" do
      digests = Array.new(3) { "uniquejobs:#{SecureRandom.hex(12)}" }
      digests.each { |d| create_lock(d, SecureRandom.hex(12)) }

      expect(described_class.call).to eq(3)
    end

    it "preserves locks for jobs in a queue" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      jid = SecureRandom.hex(12)
      create_lock(digest, jid)

      job = { "jid" => jid, "class" => "TestWorker", "queue" => "default", "lock_digest" => digest }.to_json
      redis do |conn|
        conn.call("SADD", "queues", "default")
        conn.call("LPUSH", "queue:default", job)
      end

      expect(described_class.call).to eq(0)
    end

    it "preserves locks for jobs in the retry set" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      jid = SecureRandom.hex(12)
      create_lock(digest, jid)

      job = { "jid" => jid, "class" => "TestWorker", "queue" => "default", "lock_digest" => digest }.to_json
      redis { |conn| conn.call("ZADD", "retry", Time.now.to_f.to_s, job) }

      expect(described_class.call).to eq(0)
    end

    it "preserves locks for jobs in the scheduled set" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      jid = SecureRandom.hex(12)
      create_lock(digest, jid)

      job = { "jid" => jid, "class" => "TestWorker", "queue" => "default", "lock_digest" => digest }.to_json
      redis { |conn| conn.call("ZADD", "schedule", Time.now.to_f.to_s, job) }

      expect(described_class.call).to eq(0)
    end

    it "skips digests newer than the grace period" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      jid = SecureRandom.hex(12)

      redis do |conn|
        conn.call("ZADD", digests_key, Time.now.to_f.to_s, digest)
        conn.call("HSET", "#{digest}:LOCKED", jid, '{"type":"until_executed"}')
      end

      expect(described_class.call).to eq(0)
    end

    it "handles :RUN suffix digests" do
      base_digest = "uniquejobs:#{SecureRandom.hex(12)}"
      run_digest = "#{base_digest}:RUN"
      jid = SecureRandom.hex(12)

      redis do |conn|
        conn.call("ZADD", digests_key, old_score, run_digest)
        conn.call("HSET", "#{run_digest}:LOCKED", jid, '{"type":"while_executing"}')
      end

      # Job is in queue with base digest (no :RUN suffix)
      job = { "jid" => jid, "class" => "TestWorker", "queue" => "default", "lock_digest" => base_digest }.to_json
      redis do |conn|
        conn.call("SADD", "queues", "default")
        conn.call("LPUSH", "queue:default", job)
      end

      expect(described_class.call).to eq(0)
    end

    it "preserves locks when queues are very full (fails closed)" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      create_lock(digest, SecureRandom.hex(12))

      # Fill a queue past MAX_QUEUE_LENGTH (1000)
      redis do |conn|
        conn.call("SADD", "queues", "big")
        1_001.times { |i| conn.call("LPUSH", "queue:big", "{\"jid\":\"j#{i}\"}") }
      end

      # Queue scanning is skipped — fail closed, preserve the lock
      expect(described_class.call).to eq(0)
    end

    it "reaps future-scored digests whose LOCKED hash is already gone" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      # Simulate a legacy until_expired entry: score ~1000x too far in the future,
      # LOCKED already expired via PEXPIRE.
      future_score = (Time.now.to_f + 3_600_000).to_s

      redis { |conn| conn.call("ZADD", digests_key, future_score, digest) }

      expect(described_class.call).to eq(1)
      redis do |conn|
        expect(conn.call("ZSCORE", digests_key, digest)).to be_nil
      end
    end

    it "preserves future-scored digests that still hold a LOCKED hash" do
      digest = "uniquejobs:#{SecureRandom.hex(12)}"
      jid = SecureRandom.hex(12)
      future_score = (Time.now.to_f + 3_600).to_s

      redis do |conn|
        conn.call("ZADD", digests_key, future_score, digest)
        conn.call("HSET", "#{digest}:LOCKED", jid, '{"type":"until_expired"}')
      end

      expect(described_class.call).to eq(0)
      redis do |conn|
        expect(conn.call("ZSCORE", digests_key, digest)).not_to be_nil
        expect(conn.call("EXISTS", "#{digest}:LOCKED")).to eq(1)
      end
    end
  end
end

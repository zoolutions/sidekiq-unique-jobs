# frozen_string_literal: true

module SidekiqUniqueJobs
  module Orphans
    # Ruby-based orphan reaper that detects stale locks by checking each
    # candidate digest against Sidekiq queues, retry set, scheduled set,
    # and active processes — short-circuiting on first match.
    #
    # Memory usage is O(1) per digest. No bulk loading of job data.
    # All Redis operations are individual calls so nothing blocks Redis.
    #
    # @author Mikael Henriksson <mikael@mhenrixon.com>
    class Reaper
      include SidekiqUniqueJobs::Connection
      include SidekiqUniqueJobs::Logging
      include SidekiqUniqueJobs::Timing
      include SidekiqUniqueJobs::JSON

      RUN_SUFFIX = ":RUN"
      PAGE_SIZE = 50
      GRACE_PERIOD = 10
      MAX_QUEUE_LENGTH = 1_000

      def self.call
        new.call
      end

      def initialize
        @digests = SidekiqUniqueJobs::Digests.new
        @start_time = time_source.call
        @timeout_ms = SidekiqUniqueJobs.config.reaper_timeout * 1000
        @reaper_count = SidekiqUniqueJobs.config.reaper_count
      end

      # @return [Integer] number of orphaned digests removed
      def call
        redis { |conn| execute(conn) }
      end

      private

      def execute(conn)
        orphans = find_orphans(conn)
        delete_orphans(conn, orphans)
        orphans.size
      end

      # Iterate candidate digests, checking each one against Sidekiq.
      # Short-circuits per-digest on first match found.
      def find_orphans(conn)
        orphans = []
        collect_orphans(conn, orphans, 0, max_score)

        # Second pass: digests with a future score whose :LOCKED hash is already
        # gone. Covers until_expired entries that lost their hash via PEXPIRE
        # but still sit past the byscore window (e.g. legacy ms-based scores).
        collect_expired_digests(conn, orphans) if orphans.size < @reaper_count

        orphans
      end

      def collect_orphans(conn, orphans, min_score, max)
        page = 0
        per = @reaper_count * 2

        loop do
          candidates = @digests.byscore(min_score, max, offset: page * per, count: per)
          break if candidates.empty?

          candidates.each do |digest|
            break if timeout?
            next if belongs_to_job?(conn, digest)

            orphans << digest
            break if orphans.size >= @reaper_count
          end

          break if timeout?
          break if orphans.size >= @reaper_count

          page += 1
        end
      end

      def collect_expired_digests(conn, orphans)
        page = 0
        per = @reaper_count * 2

        loop do
          # Exclusive min so we don't re-check the first pass window.
          candidates = @digests.byscore("(#{max_score}", "+inf", offset: page * per, count: per)
          break if candidates.empty?

          candidates.each do |digest|
            break if timeout?
            next if locked?(conn, digest) # still within real TTL — leave it alone

            orphans << digest
            break if orphans.size >= @reaper_count
          end

          break if timeout?
          break if orphans.size >= @reaper_count

          page += 1
        end
      end

      # Check if the digest has a matching job anywhere in Sidekiq.
      # Returns on first match — does not scan everything.
      def belongs_to_job?(conn, digest)
        return false unless locked?(conn, digest)
        return true if in_sorted_set?(conn, SCHEDULE, digest)
        return true if in_sorted_set?(conn, RETRY, digest)
        return true if enqueued?(conn, digest)

        active?(conn, digest)
      end

      # Check if the :LOCKED hash exists and has entries
      def locked?(conn, digest)
        conn.call("HLEN", "#{digest}:LOCKED").positive?
      end

      # Check a sorted set (schedule/retry) for the digest using ZSCAN MATCH.
      # The digest is embedded in the JSON member, so we pattern-match.
      def in_sorted_set?(conn, key, digest)
        return true if timeout?

        pattern = "*#{digest.delete_suffix(RUN_SUFFIX)}*"
        cursor, entries = conn.call("ZSCAN", key, "0", "MATCH", pattern, "COUNT", PAGE_SIZE.to_s)

        return true if entries.any?

        # Continue scanning if first page didn't exhaust the set
        until cursor == "0"
          return true if timeout?

          cursor, entries = conn.call("ZSCAN", key, cursor, "MATCH", pattern, "COUNT", PAGE_SIZE.to_s)
          return true if entries.any?
        end

        false
      end

      # Check all queues for the digest using string matching.
      # Iterates queue entries in pages, short-circuits on match.
      def enqueued?(conn, digest)
        return true if queues_very_full?(conn)

        needle = digest.delete_suffix(RUN_SUFFIX)
        queues = conn.call("SMEMBERS", "queues")

        queues.each do |queue|
          return true if digest_in_queue?(conn, "queue:#{queue}", needle)
        end

        false
      end

      # Check active processes for the digest in their work hashes.
      def active?(conn, digest)
        return true if timeout?

        needle = digest.delete_suffix(RUN_SUFFIX)
        procs = conn.call("SMEMBERS", PROCESSES)

        procs.each do |process|
          return true if timeout?

          valid = conn.call("EXISTS", process)
          next unless valid.positive?

          workers = conn.call("HGETALL", "#{process}:work")

          workers.each_slice(2) do |_tid, job_json|
            item = safe_load_json(job_json)
            next unless item.is_a?(Hash)

            payload = safe_load_json(item[PAYLOAD])
            next unless payload.is_a?(Hash)

            lock_digest = payload[LOCK_DIGEST]
            return true if lock_digest && lock_digest.delete_suffix(RUN_SUFFIX) == needle
          end
        end

        false
      end

      def digest_in_queue?(conn, queue_key, needle)
        initial_size = conn.call("LLEN", queue_key)
        deleted_size = 0
        page = 0

        loop do
          return true if timeout?

          range_start = [(page * PAGE_SIZE) - deleted_size, 0].max
          range_end = range_start + PAGE_SIZE - 1
          entries = conn.call("LRANGE", queue_key, range_start, range_end)

          break if entries.empty?

          entries.each do |entry|
            return true if entry.include?(needle)
          end

          page += 1
          current_size = conn.call("LLEN", queue_key)
          deleted_size = [initial_size - current_size, 0].max
        end

        false
      end

      # Skip queue scanning when queues are very large — too expensive
      # and likely means the system is under load anyway.
      def queues_very_full?(conn)
        total = 0
        queues = conn.call("SMEMBERS", "queues")

        queues.each do |queue|
          total += conn.call("LLEN", "queue:#{queue}")
          return true if total > MAX_QUEUE_LENGTH
        end

        false
      end

      def delete_orphans(conn, orphans)
        return if orphans.empty?

        BatchDelete.call(orphans, conn)
      end

      def max_score
        (Time.now - SidekiqUniqueJobs.config.reaper_timeout - GRACE_PERIOD).to_f
      end

      def timeout?
        (time_source.call - @start_time) >= @timeout_ms
      end
    end
  end
end

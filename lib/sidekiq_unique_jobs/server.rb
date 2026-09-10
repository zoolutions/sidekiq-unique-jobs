# frozen_string_literal: true

module SidekiqUniqueJobs
  # Server-side lifecycle management for sidekiq-unique-jobs.
  #
  # Handles startup (migration, metrics, reaper) and shutdown (flush, cleanup).
  #
  # @author Mikael Henriksson <mikael@mhenrixon.com>
  class Server
    include SidekiqUniqueJobs::Connection
    include SidekiqUniqueJobs::Logging

    DEATH_HANDLER = (lambda do |job, _ex|
      return unless (digest = job["lock_digest"])

      SidekiqUniqueJobs::Digests.new.delete_by_digest(digest)
    end).freeze

    # Drift factor added to reaper interval for mutex TTL
    DRIFT_FACTOR = 0.02

    class << self
      attr_reader :metrics

      def configure(config)
        config.on(:startup)  { start }
        config.on(:shutdown) { stop }

        return unless config.respond_to?(:death_handlers)

        config.death_handlers << DEATH_HANDLER
      end

      def start
        SidekiqUniqueJobs::UpgradeLocks.call
        start_metrics
        start_reaper
        start_resurrector
      end

      def stop
        @reaper_task&.shutdown
        @resurrector_task&.shutdown
        @flush_task&.shutdown
        @metrics&.flush
        release_reaper_mutex
      end

      # Run the reaper once (used by tests and manual invocation).
      # @return [Integer] number of stale digests removed
      def reap
        log_info("Reaper cycle starting")

        count = Orphans::Reaper.call

        if count.positive?
          log_info("Reaper removed #{count} orphaned digests")
        else
          log_info("Reaper found no orphans")
        end
        count
      rescue StandardError => ex
        log_error("Reaper error: #{ex.class}: #{ex.message}")
        0
      end

      private

      # ── Reaper lifecycle ──────────────────────────────────────────

      # Try to become THE reaper. Only one process wins via SET NX EX.
      # Winner starts the TimerTask; losers do nothing (the resurrector
      # will pick up if the winner dies).
      def start_reaper
        if reaper_disabled?
          log_info("Reaper is disabled (config.reaper=#{SidekiqUniqueJobs.config.reaper.inspect})")
          return
        end

        warn_if_lua_reaper_configured

        return unless register_reaper_process

        interval = SidekiqUniqueJobs.config.reaper_interval
        log_info("Starting reaper (interval=#{interval}s, count=#{SidekiqUniqueJobs.config.reaper_count})")

        @reaper_task = SidekiqUniqueJobs::TimerTask.new(
          run_now: false,
          execution_interval: interval,
        ) do
          refresh_reaper_mutex
          reap
        end
        @reaper_task.execute
      end

      # ── Resurrector ───────────────────────────────────────────────
      # Runs on ALL processes. Periodically checks if the reaper mutex
      # has expired (holder died). If so, tries to become the new reaper.

      def start_resurrector
        return if reaper_disabled?
        return if @reaper_task # we ARE the reaper, no need to resurrect

        interval = SidekiqUniqueJobs.config.reaper_interval * 2
        @resurrector_task = SidekiqUniqueJobs::TimerTask.new(
          run_now: false,
          execution_interval: interval,
        ) do
          resurrect_reaper
        end
        @resurrector_task.execute
      end

      def resurrect_reaper
        return if @reaper_task&.running?
        return if reaper_registered?

        log_info("Reaper died — taking over")
        start_reaper
      rescue StandardError => ex
        log_error("Resurrector error: #{ex.class}: #{ex.message}")
      end

      # ── Redis mutex ───────────────────────────────────────────────

      # SET NX EX — only succeeds if no reaper is registered
      def register_reaper_process
        SidekiqUniqueJobs.redis do |conn|
          conn.call("SET", UNIQUE_REAPER, Process.pid.to_s, "NX", "EX", mutex_ttl.to_s) == "OK"
        end
      rescue StandardError
        false
      end

      # Refresh TTL each cycle so the key doesn't expire between runs.
      # Only refresh when we still own the mutex — a plain SET would overwrite
      # a successor that registered after our TTL lapsed.
      def refresh_reaper_mutex
        SidekiqUniqueJobs.redis do |conn|
          owner = conn.call("GET", UNIQUE_REAPER)
          next unless owner == Process.pid.to_s

          conn.call("SET", UNIQUE_REAPER, Process.pid.to_s, "EX", mutex_ttl.to_s)
        end
      rescue StandardError
        # non-critical
      end

      def warn_if_lua_reaper_configured
        return unless SidekiqUniqueJobs.config.reaper == :lua

        SidekiqUniqueJobs::Deprecation.warn(
          "`config.reaper = :lua` was removed in v9; the Ruby reaper always runs. " \
          "Set `config.reaper = :ruby` (or `true`) to silence this warning.",
        )
      end

      # Check if any process currently holds the reaper mutex
      def reaper_registered?
        SidekiqUniqueJobs.redis do |conn|
          conn.call("EXISTS", UNIQUE_REAPER).positive?
        end
      rescue StandardError
        true # assume registered if we can't check — safe default
      end

      # Release on shutdown, but only if we own it
      def release_reaper_mutex
        SidekiqUniqueJobs.redis do |conn|
          owner = conn.call("GET", UNIQUE_REAPER)
          conn.call("DEL", UNIQUE_REAPER) if owner == Process.pid.to_s
        end
      rescue StandardError
        # non-critical
      end

      def mutex_ttl
        interval = SidekiqUniqueJobs.config.reaper_interval
        interval + (interval * DRIFT_FACTOR).ceil
      end

      def reaper_disabled?
        reaper = SidekiqUniqueJobs.config.reaper
        [nil, false, :none].include?(reaper)
      end

      # ── Metrics ───────────────────────────────────────────────────

      def start_metrics
        @metrics = LockMetrics.new

        SidekiqUniqueJobs.reflect do |on|
          on.unlock_failed { |item| @metrics.track(:unlock_failed, item) }
          on.execution_failed { |item, *| @metrics.track(:execution_failed, item) }
        end

        @flush_task = SidekiqUniqueJobs::TimerTask.new(run_now: false, execution_interval: 60) do
          @metrics.flush
        end
        @flush_task.execute
      end
    end
  end
end

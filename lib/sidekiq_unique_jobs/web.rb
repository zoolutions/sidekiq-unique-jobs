# frozen_string_literal: true

require_relative "web/helpers"

module SidekiqUniqueJobs
  # Utility module to help manage unique keys in redis.
  # Useful for deleting keys that for whatever reason wasn't deleted
  # @author Mikael Henriksson <mikael@mhenrixon.com>
  module Web
    def self.registered(app)
      app.helpers Web::Helpers

      app.get "/locks" do
        @filter         = h(url_params("filter") || "*")
        @filter         = "*" if @filter == ""
        @count          = h(url_params("count") || 100).to_i
        @current_cursor = h(url_params("cursor")).to_i
        @prev_cursor    = h(url_params("prev_cursor")).to_i

        @total_size, @next_cursor, @locks = digests.page(
          cursor: @current_cursor,
          pattern: @filter,
          page_size: @count,
        )

        @metrics_by_type = SidekiqUniqueJobs::LockMetrics.by_type(minutes: 60)

        erb(unique_template(:locks))
      end

      app.get "/locks/delete_all" do
        digests.delete_by_pattern("*", count: digests.count)
        redirect_to "locks"
      end

      app.get "/locks/:digest" do
        @digest = h(route_params(:digest))
        @lock   = SidekiqUniqueJobs::Lock.new(@digest)

        erb(unique_template(:lock))
      end

      app.get "/locks/:digest/delete" do
        digests.delete_by_digest(h(route_params(:digest)))
        redirect_to "locks"
      end

      app.get "/locks/:digest/jobs/:job_id/delete" do
        @digest = h(route_params(:digest))
        @job_id = h(route_params(:job_id))
        @lock   = SidekiqUniqueJobs::Lock.new(@digest)
        @lock.unlock(@job_id)

        redirect_to "locks/#{@lock.key}"
      end
    end
  end
end

begin
  require "delegate" unless defined?(DelegateClass)
  require "sidekiq/web" unless defined?(Sidekiq::Web)

  Sidekiq::Web.configure do |config|
    config.register_extension(
      SidekiqUniqueJobs::Web,
      name: "unique_jobs",
      tab: ["Locks"],
      index: %w[locks],
    )
  end
rescue NameError, LoadError => ex
  SidekiqUniqueJobs.logger.error(ex)
end

# frozen_string_literal: true

# :nocov:

# This class showcase a job that is considered unique disregarding any worker classes.
# Currently it will only be compared to other jobs that are disregarding worker classes.
# If one were to compare the unique keys generated against a job that doesn't have the
# worker class removed it won't work.
#
# The following specs cover this functionality:
#   - https://github.com/zoolutions/sidekiq-unique-jobs/blob/master/spec/lib/sidekiq_unique_jobs/client/middleware_spec.rb
#   - https://github.com/zoolutions/sidekiq-unique-jobs/blob/master/spec/lib/sidekiq_unique_jobs/unique_args_spec.rb
class UniqueAcrossWorkersJob
  include Sidekiq::Worker

  sidekiq_options lock: :until_executed, unique_across_workers: true

  def perform(one, two)
    [one, two]
  end
end

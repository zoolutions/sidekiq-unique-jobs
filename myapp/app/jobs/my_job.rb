# frozen_string_literal: true

class MyJob
  include Sidekiq::Job

  sidekiq_options queue: :my_queue_name,
                  # Locks when the client pushes the job to the queue.
                  # The queue will be unlocked when the server starts processing the job.
                  # The server then goes on to creating a runtime lock for the job to prevent
                  # simultaneous jobs from being executed. As soon as the server starts
                  # processing a job, the client can push the same job to the queue.
                  # https://github.com/zoolutions/sidekiq-unique-jobs#until-and-while-executing
                  lock: :until_and_while_executing,
                  # search in logs SidekiqUniqueJobs keyword to find duplicates
                  log_duplicate_payload: true

  def perform(my_id)
    logger.info(my_id)
  end
end

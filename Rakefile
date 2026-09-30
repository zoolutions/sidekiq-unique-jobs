# frozen_string_literal: true

Dir.glob("#{File.expand_path(__dir__)}/lib/tasks/**/*.rake").each { |f| import f }

begin
  require "reek/rake/task"
  Reek::Rake::Task.new(:reek) do |t|
    t.name          = "reek"
    t.config_file   = ".reek.yml"
    t.source_files  = "."
    t.reek_opts     = %w[
      --line-numbers
      --color
      --documentation
      --progress
      --single-line
      --sort-by smelliness
    ].join(" ")
    t.fail_on_error = true
    t.verbose       = true
  end
rescue LoadError
  puts "Reek is currently unavailable"

  desc "Template Reek task"
  task :reek do
    puts "Should be running reek"
  end
end

def changed_files(pedantry)
  `git diff-tree --no-commit-id --name-only -r HEAD~#{pedantry} HEAD`
    .split("\n").select { |f| f.match(/(\.rb\z)|Rakefile/) && File.exist?(f) && !f.include?("db") }
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:rubocop) do |task|
    # task.patterns = changed_files(5)
    task.options = %w[-DEP --format fuubar]
  end
rescue LoadError
  puts "Rubocop is currently unavailable"

  desc "Template Rubocop task"
  task :rubocop do
    puts "Should be running rubocop"
  end
end

desc "Runs style validations"
task style: [:reek, :rubocop]

begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:rspec) do |t|
    t.rspec_opts = "--format Fuubar --format Nc"
  end
rescue LoadError
  puts "RSpec is currently not available"

  desc "Template RSpec task"
  task :rspec do
    puts "Should be running rspec"
  end
end

begin
  require "yard"
  YARD::Rake::YardocTask.new(:yard) do |t|
    t.files   = %w[lib/sidekiq_unique_jobs/**/*.rb]
    t.options = %w[
      --exclude lib/sidekiq_unique_jobs/testing.rb
      --exclude lib/sidekiq_unique_jobs/web/helpers.rb
      --exclude lib/redis.rb
      --no-private
      --embed-mixins
      --markup=markdown
      --markup-provider=redcarpet
      --readme README.md
      --files CHANGELOG.md,LICENSE.txt
    ]
    t.stats_options = %w[
      --exclude lib/sidekiq_unique_jobs/testing.rb
      --exclude lib/sidekiq_unique_jobs/web/helpers.rb
      --no-private
      --compact
      --list-undoc
    ]
  end
rescue LoadError
  puts "Yard is currently unavailable"

  desc "Template Yard task"
  task :yard do
    puts "Should be running yard"
  end
end

task default: [:style, :rspec, :yard]

namespace :appraisal do
  namespace :rspec do
    desc "Runs rspec for all appraisals"
    task :all do
      sh("bundle exec appraisal rspec")
    end

    desc "Runs rspec for older appraisals than sidekiq 6"
    task :pre_sidekiq6 do
      sh("bundle exec appraisal sidekiq-4.0 rspec")
      sh("bundle exec appraisal sidekiq-4.1 rspec")
      sh("bundle exec appraisal sidekiq-4.2 rspec")
      sh("bundle exec appraisal sidekiq-5.0 rspec")
      sh("bundle exec appraisal sidekiq-5.1 rspec")
      sh("bundle exec appraisal sidekiq-5.2 rspec")
    end

    desc "Runs rspec for appraisals containing sidekiq 6 or greater"
    task :post_sidekiq6 do
      sh("bundle exec appraisal sidekiq-6.0 rspec")
      sh("bundle exec appraisal sidekiq-develop rspec")
    end

    task default: [:all]
  end
end

desc "Build gem and verify contents"
task :build do
  sh("gem build sidekiq-unique-jobs.gemspec --strict")
  gem_file = Dir["sidekiq-unique-jobs-*.gem"].first
  sh("gem unpack #{gem_file} --target /tmp/gem-verify")
  puts "\n=== Gem contents ==="
  sh("find /tmp/gem-verify -type f | sort")
  sh("rm -rf /tmp/gem-verify #{gem_file}")
end

# `rake release[X.Y.Z]` lives in rakelib/release.rake (the zoolutions release
# kit, shared verbatim across the gems); `bin/release` is its front door.

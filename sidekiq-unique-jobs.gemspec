# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sidekiq_unique_jobs/version"

Gem::Specification.new do |spec|
  spec.name        = "sidekiq-unique-jobs"
  spec.version     = SidekiqUniqueJobs::VERSION
  spec.authors     = ["Mikael Henriksson"]
  spec.email       = ["mikael@mhenrixon.com"]
  spec.homepage    = "https://github.com/zoolutions/sidekiq-unique-jobs"
  spec.license     = "MIT"
  spec.summary     = <<~SUMMARY
    Sidekiq middleware that prevents duplicates jobs
  SUMMARY
  spec.description = <<~DESCRIPTION
    Prevents simultaneous Sidekiq jobs with the same unique arguments to run.
    Highly configurable to suite your specific needs.
  DESCRIPTION

  raise "RubyGems 2.0 or newer is required to protect against public gem pushes." unless spec.respond_to?(:metadata)

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/zoolutions/sidekiq-unique-jobs/issues",
    "documentation_uri" => "https://sidekiq-unique-jobs.zoolutions.llc",
    "source_code_uri" => "https://github.com/zoolutions/sidekiq-unique-jobs/tree/v#{spec.version}",
    "changelog_uri" => "https://github.com/zoolutions/sidekiq-unique-jobs/blob/main/CHANGELOG.md",
    "funding_uri" => "https://github.com/sponsors/mhenrixon",
    "rubygems_mfa_required" => "true",
  }

  spec.bindir        = "bin"
  spec.executables   = %w[uniquejobs]

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").select do |file|
      file.match(%r{^(lib/sidekiq|lib/sidekiq-|bin/uniquejobs|README|LICENSE|CHANGELOG)})
    end
  end

  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "concurrent-ruby", "~> 1.0", ">= 1.0.5"
  spec.add_dependency "sidekiq", ">= 8.0.0", "< 10.0.0"
  spec.add_dependency "thor", ">= 1.0", "< 3.0"
end

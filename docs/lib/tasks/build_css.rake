# frozen_string_literal: true

# Build the daisyUI/Tailwind stylesheet into app/assets/builds/application.css so
# Propshaft can serve it. Runs as part of assets:precompile (production/Docker);
# `bin/dev` runs the watch variant in development.
namespace :css do
  desc "Build the Tailwind + daisyUI stylesheet via bun"
  task build: :environment do
    sh "bun run build:css"
  end
end

Rake::Task["assets:precompile"].enhance([ "css:build" ]) if Rake::Task.task_defined?("assets:precompile")

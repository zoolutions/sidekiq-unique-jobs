# frozen_string_literal: true

require "rails_helper"
require "sidekiq_unique_jobs"

# The Configuration reference page is generated from ConfigReference::GROUPS.
# This spec keeps that data honest against the REAL SidekiqUniqueJobs::Config, in
# both directions, so the reference can't silently drift from the gem:
#
#   1. Every documented option must be a real Config struct member.
#   2. Every real struct member must be either documented or explicitly
#      allowlisted as internal — so a NEW config option fails the build until
#      someone documents it (or marks it internal on purpose).
#
# Config is a Concurrent::MutableStruct, so its options are the struct members
# (config.members), not `foo=` writer methods.
RSpec.describe "Configuration reference drift", type: :model do
  let(:real_members) do
    SidekiqUniqueJobs::Config.default.members.map(&:to_s).sort.uniq
  end

  let(:documented) { ConfigReference.documented_names.sort }
  let(:internal)   { ConfigReference::INTERNAL_ONLY.sort }

  it "documents only real configuration members" do
    unknown = documented - real_members
    expect(unknown).to be_empty,
                       "ConfigReference documents options that aren't SidekiqUniqueJobs::Config members: #{unknown.inspect}"
  end

  it "documents (or allowlists) every real configuration member" do
    undocumented = real_members - documented - internal
    expect(undocumented).to be_empty,
                            "New SidekiqUniqueJobs::Config members are neither documented nor allowlisted: " \
                            "#{undocumented.inspect}. Add each to ConfigReference::GROUPS (to document it) " \
                            "or ConfigReference::INTERNAL_ONLY (to mark it internal)."
  end

  it "has no overlap between documented and internal lists" do
    overlap = documented & internal
    expect(overlap).to be_empty,
                       "Options appear in both GROUPS and INTERNAL_ONLY: #{overlap.inspect}"
  end
end

# frozen_string_literal: true

# The single source of truth for the Configuration reference page — every global
# option as {name, type, default, description}, in groups. The page renders
# grouped PropTables from GROUPS; the drift spec (spec/config_reference_spec.rb)
# checks both directions against the real SidekiqUniqueJobs::Config struct
# members, so a renamed or added option fails the build until this list is
# updated.
#
# SidekiqUniqueJobs::Config is a Concurrent::MutableStruct, so its "accessors"
# are the struct members (config.members). Defaults come from the constants in
# lib/sidekiq_unique_jobs/config.rb.
#
# INTERNAL_ONLY lists members that are deliberately NOT surfaced here — injected
# collaborators (logger), derived registries (locks, strategies), and values set
# indirectly. Keeping them in an explicit allowlist means a NEW undocumented
# member still trips the spec.
module ConfigReference
  GROUPS = {
    "Locking" => [
      { name: "enabled", type: "Boolean", default: "true", desc: "Master switch. Set false to disable uniqueness globally (e.g. in tests)." },
      { name: "lock_ttl", type: "Integer, nil", default: "nil", desc: "Default lock expiration in seconds; nil means the lock never expires on its own." },
      { name: "lock_timeout", type: "Integer", default: "0", desc: "Retained for compatibility. v9 lock acquisition is always non-blocking — this value does not cause waiting. Use an on_conflict strategy (e.g. :reschedule) instead." },
      { name: "lock_prefix", type: "String", default: '"uniquejobs"', desc: "Prefix for every Redis lock key." },
      { name: "lock_info", type: "Boolean", default: "false", desc: "Store extra lock metadata (worker, args, timestamp) for debugging. Adds overhead." },
      { name: "on_conflict", type: "Symbol, Hash, nil", default: "nil", desc: "Global default conflict strategy when a worker doesn't set its own; nil defers entirely to per-worker config." }
    ],
    "Reaper (orphan cleanup)" => [
      { name: "reaper", type: "Symbol, Boolean", default: ":ruby", desc: "Orphan-lock reaper mode: :ruby/true (default), or :none/false to disable. :lua is accepted but ignored (deprecated in v9)." },
      { name: "reaper_count", type: "Integer", default: "1000", desc: "Maximum orphaned locks reaped per cycle." },
      { name: "reaper_interval", type: "Integer", default: "600", desc: "Seconds between reaper runs (default 10 minutes)." },
      { name: "reaper_timeout", type: "Integer", default: "10", desc: "Maximum seconds a single reaper run may take before it stops." },
      { name: "reaper_resurrector_interval", type: "Integer", default: "3600", desc: "Unused in v9 (resurrector interval is derived from reaper_interval). Kept for compatibility." },
      { name: "reaper_resurrector_enabled", type: "Boolean", default: "false", desc: "Unused in v9 (resurrector always runs on non-reaper processes). Kept for compatibility." }
    ],
    "Digest & storage" => [
      { name: "digest_algorithm", type: "Symbol", default: ":legacy", desc: "How the uniqueness digest is hashed: :legacy (MD5) or :modern (FIPS-compatible). Changing this changes every digest." },
      { name: "max_history", type: "Integer", default: "1000", desc: "Unused in v9 (changelog history was removed). Kept so existing ARGV slots in Lua scripts stay stable." }
    ],
    "Execution & errors" => [
      { name: "locksmith_executor", type: "Executor, nil", default: "nil", desc: "Unused in v9 (Locksmith is synchronous). Lazily building this pool is unnecessary; kept for compatibility." },
      { name: "raise_on_config_error", type: "Boolean", default: "false", desc: "Raise instead of warn when a worker declares an invalid lock configuration." },
      { name: "logger_enabled", type: "Boolean", default: "true", desc: "Enable the gem's internal logging." },
      { name: "debug_lua", type: "Boolean", default: "false", desc: "Log Lua script execution. Slow — for debugging only." }
    ]
  }.freeze

  # Config struct members deliberately not documented on the reference page:
  # injected collaborators, derived registries populated by add_lock/add_strategy,
  # and values fetched at runtime. Listed explicitly so a NEW undocumented member
  # still fails the drift spec.
  INTERNAL_ONLY = %w[
    logger
    locks
    strategies
    current_redis_version
  ].freeze

  module_function

  # Every documented option name, flat — used by the page and the drift spec.
  def documented_names
    GROUPS.values.flatten.map { |o| o[:name] }
  end
end

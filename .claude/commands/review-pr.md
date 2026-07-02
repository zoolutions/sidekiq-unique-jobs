---
description: Review a GitHub pull request for code quality, patterns, and best practices
model: opus
argument-hint: "PR URL or number (e.g., 923 or https://github.com/mhenrixon/sidekiq-unique-jobs/pull/923)"
---

# PR Review

Review PR for pattern compliance and issues. Be concise.

## Workflow

1. Fetch PR details and diff via `mcp__github__pull_request_read`
2. Categorize files by type
3. Check for pattern violations
4. Output structured review

## Pattern Violations to Check

```ruby
# WRONG -> RIGHT
Direct Redis commands in Ruby    -> Lua scripts for atomicity
redis.call without error handling -> Proper pcall/error handling in Lua
Hardcoded Redis key names        -> SidekiqUniqueJobs::Key
Missing lock cleanup             -> Always handle full lock lifecycle
rescue StandardError => nil      -> Specific error handling
Thread.new for concurrency       -> Use Concurrent::* primitives
```

## Output Format

```
## Files Requiring Manual Review

| File | Reason |
|------|--------|
| lib/sidekiq_unique_jobs/lock/foo.rb | New lock type, verify lifecycle |
| lib/sidekiq_unique_jobs/lua/bar.lua | Redis atomicity, check edge cases |

## Critical Issues

- `lib/sidekiq_unique_jobs/locksmith.rb:45` - Direct Redis call, should use Lua
- `lib/sidekiq_unique_jobs/lock/foo.rb:12` - Missing unlock in error path

## Suggestions (non-blocking)

- Consider extracting X to shared Lua function

## Verdict

**Request Changes** - Fix atomicity issues before merge
```

## Tools

```
mcp__github__pull_request_read
  method: "get"        -> PR details
  method: "get_diff"   -> Changes
  method: "get_files"  -> File list
  method: "get_status" -> CI status

bundle exec rubocop    -> Style checks
bundle exec rspec      -> Tests
```

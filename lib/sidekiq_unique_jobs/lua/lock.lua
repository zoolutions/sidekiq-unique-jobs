local locked  = KEYS[1]
local digests = KEYS[2]

local job_id    = ARGV[1]
local pttl      = tonumber(ARGV[2])
local lock_type = ARGV[3]
local limit     = tonumber(ARGV[4])
local metadata  = ARGV[5]

--------  BEGIN injected arguments --------
local current_time = tonumber(ARGV[6])
---------  END injected arguments ---------

if redis.call("HEXISTS", locked, job_id) == 1 then
  return job_id
end

if redis.call("HLEN", locked) >= limit then
  return nil
end

redis.call("HSET", locked, job_id, metadata)

-- current_time is epoch seconds (SidekiqUniqueJobs.now_f).
-- pttl is milliseconds (LockConfig multiplies TTL seconds by 1000).
-- Digests ZSET scores must stay in seconds so the reaper's byscore window
-- (also seconds) can find expired until_expired entries.
local score
if lock_type == "until_expired" and pttl and pttl > 0 then
  score = current_time + (pttl / 1000.0)
else
  score = current_time
end

local digest = string.gsub(locked, ":LOCKED$", "")
redis.call("ZADD", digests, score, digest)

if pttl and pttl > 0 then
  redis.call("PEXPIRE", locked, pttl)
end

return job_id

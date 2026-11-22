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

local score
if lock_type == "until_expired" and pttl and pttl > 0 then
  -- current_time is seconds, pttl is ms; the reaper compares scores in seconds
  score = current_time + pttl / 1000
else
  score = current_time
end

local digest = string.gsub(locked, ":LOCKED$", "")
redis.call("ZADD", digests, score, digest)

if pttl and pttl > 0 then
  redis.call("PEXPIRE", locked, pttl)
end

return job_id

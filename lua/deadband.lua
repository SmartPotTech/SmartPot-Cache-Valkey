-- deadband.lua
-- KEYS[1] = crop deadband key (e.g., "crop:{id}:deadband")
-- ARGV[1] = temperature (float)
-- ARGV[2] = humidity (float)
-- ARGV[3] = ph (float)
-- ARGV[4] = tds (float)
-- ARGV[5] = soil_moisture (float)
-- ARGV[6] = max_age_seconds (float, default 60.0)
-- ARGV[7] = current_timestamp (float)
-- Returns 1 if reading exceeds deadband or baseline expired (should record/publish), 0 if filtered out

local key = KEYS[1]
local temp = tonumber(ARGV[1])
local rh = tonumber(ARGV[2])
local ph = tonumber(ARGV[3])
local tds = tonumber(ARGV[4])
local moisture = tonumber(ARGV[5])
local max_age = tonumber(ARGV[6]) or 60.0
local now = tonumber(ARGV[7]) or os.time()

local prev = redis.call('HMGET', key, 't', 'rh', 'ph', 'tds', 'm', 'ts')
local prev_t = tonumber(prev[1])
local prev_rh = tonumber(prev[2])
local prev_ph = tonumber(prev[3])
local prev_tds = tonumber(prev[4])
local prev_m = tonumber(prev[5])
local prev_ts = tonumber(prev[6])

local update = false
if not prev_ts or (now - prev_ts) >= max_age then
    update = true
elseif prev_t and temp and math.abs(temp - prev_t) >= 0.1 then
    update = true
elseif prev_rh and rh and math.abs(rh - prev_rh) >= 0.4 then
    update = true
elseif prev_ph and ph and math.abs(ph - prev_ph) >= 0.03 then
    update = true
elseif prev_tds and tds and math.abs(tds - prev_tds) >= 15.0 then
    update = true
elseif prev_m and moisture and math.abs(moisture - prev_m) >= 0.5 then
    update = true
end

if update then
    redis.call('HSET', key,
        't', tostring(temp or 0.0),
        'rh', tostring(rh or 0.0),
        'ph', tostring(ph or 0.0),
        'tds', tostring(tds or 0.0),
        'm', tostring(moisture or 0.0),
        'ts', tostring(now)
    )
    redis.call('EXPIRE', key, math.max(300, math.floor(max_age * 2)))
    return 1
end

return 0

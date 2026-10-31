#!lua name=smartpot
-- SmartPot Atomic Functions for Valkey
-- 1. deadband_check_and_update: Compares telemetry with cached baseline and updates if delta exceeded.
-- 2. mqtt_dedup_and_rate_limit: Leaky-bucket GCRA rate limiting and packet sequence deduplication.

local function deadband_check_and_update(keys, args)
    local key = keys[1]
    local temp = tonumber(args[1])
    local rh = tonumber(args[2])
    local ph = tonumber(args[3])
    local tds = tonumber(args[4])
    local moisture = tonumber(args[5])
    local max_age = tonumber(args[6]) or 60.0
    local now = tonumber(args[7]) or os.time()

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
end

local function mqtt_dedup_and_rate_limit(keys, args)
    local dedup_key = keys[1]
    local gcra_key = keys[2]
    local seq_id = args[1]
    local rate = tonumber(args[2]) or 10.0
    local burst = tonumber(args[3]) or 20.0
    local now = tonumber(args[4]) or os.time()

    -- Deduplication check
    if seq_id and seq_id ~= '' and seq_id ~= '0' then
        local exists = redis.call('EXISTS', dedup_key)
        if exists == 1 then
            return 2 -- Duplicate packet detected
        end
    end

    -- GCRA Leaky Bucket
    local emission_interval = 1.0 / rate
    local delay_tolerance = burst * emission_interval
    local tat = tonumber(redis.call('GET', gcra_key)) or now

    local new_tat = math.max(tat, now) + emission_interval
    local allow_at = new_tat - delay_tolerance

    if now < allow_at then
        return 0 -- Rate limit exceeded
    end

    redis.call('SET', gcra_key, tostring(new_tat), 'EX', math.ceil(delay_tolerance + 10))

    if seq_id and seq_id ~= '' and seq_id ~= '0' then
        redis.call('SET', dedup_key, '1', 'EX', 60)
    end

    return 1 -- Allowed
end

redis.register_function('deadband_check_and_update', deadband_check_and_update)
redis.register_function('mqtt_dedup_and_rate_limit', mqtt_dedup_and_rate_limit)

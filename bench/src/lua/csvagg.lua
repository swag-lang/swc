local ROWS = 400000
local REGIONS = { "EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH" }

local floor = math.floor
local byte = string.byte
local sub = string.sub

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

-- ---- data generation (not timed) ----
local lines = {}
for j = 0, ROWS - 1 do
    local region = REGIONS[(rnd() % 8) + 1]
    local y = 2024 + (rnd() % 3)
    local m = 1 + (rnd() % 12)
    local d = 1 + (rnd() % 28)
    local qty = 1 + (rnd() % 50)
    local cents = 100 + (rnd() % 99900)
    lines[j + 1] = string.format("%d,%s,%d-%02d-%02d,%d,%d.%02d",
        j, region, y, m, d, qty, floor(cents / 100), cents % 100)
end
local text = table.concat(lines, "\n")
lines = nil

-- ---- timed work ----
local t0 = os.clock()

local n = #text
local agg = {}
local nkeys = 0
local keys = {}
local pos = 1
local rows = 0
while pos <= n do
    local eol = pos
    while eol <= n and byte(text, eol) ~= 10 do eol = eol + 1 end

    -- field 0: id
    local p = pos
    while p < eol and byte(text, p) ~= 44 do p = p + 1 end
    p = p + 1

    -- field 1: region
    local rs = p
    while p < eol and byte(text, p) ~= 44 do p = p + 1 end
    local region = sub(text, rs, p - 1)
    p = p + 1

    -- field 2: date (skipped)
    while p < eol and byte(text, p) ~= 44 do p = p + 1 end
    p = p + 1

    -- field 3: qty
    local qty = 0
    while p < eol and byte(text, p) ~= 44 do
        qty = qty * 10 + (byte(text, p) - 48)
        p = p + 1
    end
    p = p + 1

    -- field 4: price
    local ip = 0
    while p < eol and byte(text, p) ~= 46 do
        ip = ip * 10 + (byte(text, p) - 48)
        p = p + 1
    end
    p = p + 1
    local fr = 0
    while p < eol do
        fr = fr * 10 + (byte(text, p) - 48)
        p = p + 1
    end
    local price = ip + fr / 100.0

    local e = agg[region]
    if e == nil then
        agg[region] = { 1, qty, qty * price, price }
        nkeys = nkeys + 1
        keys[nkeys] = region
    else
        e[1] = e[1] + 1
        e[2] = e[2] + qty
        e[3] = e[3] + qty * price
        if price > e[4] then e[4] = price end
    end

    rows = rows + 1
    pos = eol + 1
end

table.sort(keys)
local check = rows
for k = 1, nkeys do
    local e = agg[keys[k]]
    check = check + k * (floor(e[3] * 100.0 + 0.5) % 1000003)
    check = check + e[1] + e[2] + floor(e[4] * 100.0 + 0.5)
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

local DATA_SIZE = 1048576
local WORDS = 512
local HASH_SIZE = 65536
local WINDOW = 32768
local MIN_MATCH = 4
local MAX_MATCH = 258
local MAX_CHAIN = 32

local floor = math.floor

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

-- ---- data generation (not timed) ----
local letters = {}
local wordStart = {}
local wordLen = {}
local used = 0
for k = 0, WORDS - 1 do
    local len = 2 + (rnd() % 8)
    wordStart[k] = used
    wordLen[k] = len
    for j = 0, len - 1 do
        letters[used + j] = 97 + (rnd() % 26)
    end
    used = used + len
end

local n = DATA_SIZE
local data = {}
local pos = 0
while pos < n do
    local w = rnd() % WORDS
    local j = 0
    while j < wordLen[w] and pos < n do
        data[pos] = letters[wordStart[w] + j]
        pos = pos + 1
        j = j + 1
    end
    if pos < n then
        data[pos] = 32
        pos = pos + 1
    end
end

-- ---- timed work ----
local t0 = os.clock()

local function hashAt(d, p)
    return (((d[p] * 33 + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE
end

local head = {}
for k = 0, HASH_SIZE - 1 do head[k] = -1 end
local prev = {}
for k = 0, WINDOW - 1 do prev[k] = -1 end

local comp = {}
local csize = 0

local i = 0
while i + MIN_MATCH <= n do
    local best = 0
    local dist = 0
    local limit = MAX_MATCH
    if n - i < MAX_MATCH then limit = n - i end
    local h = hashAt(data, i)
    local cand = head[h]
    local chain = 0
    while cand >= 0 and i - cand < WINDOW and chain < MAX_CHAIN do
        local l = 0
        while l < limit and data[cand + l] == data[i + l] do
            l = l + 1
        end
        if l > best then
            best = l
            dist = i - cand
            if l == limit then break end
        end
        cand = prev[cand % WINDOW]
        chain = chain + 1
    end

    prev[i % WINDOW] = head[h]
    head[h] = i

    if best >= MIN_MATCH then
        comp[csize] = 1
        comp[csize + 1] = best - MIN_MATCH
        comp[csize + 2] = (dist - 1) % 256
        comp[csize + 3] = floor((dist - 1) / 256)
        csize = csize + 4
        for p = i + 1, i + best - 1 do
            if p + MIN_MATCH <= n then
                local hp = hashAt(data, p)
                prev[p % WINDOW] = head[hp]
                head[hp] = p
            end
        end
        i = i + best
    else
        comp[csize] = 0
        comp[csize + 1] = data[i]
        csize = csize + 2
        i = i + 1
    end
end

while i < n do
    comp[csize] = 0
    comp[csize + 1] = data[i]
    csize = csize + 2
    i = i + 1
end

-- ---- decompress and verify ----
local out = {}
local o = 0
local c = 0
while c < csize do
    if comp[c] == 0 then
        out[o] = comp[c + 1]
        o = o + 1
        c = c + 2
    else
        local len = comp[c + 1] + MIN_MATCH
        local back = comp[c + 2] + comp[c + 3] * 256 + 1
        for k = 1, len do
            out[o] = out[o - back]
            o = o + 1
        end
        c = c + 4
    end
end

local same = o == n
local k = 0
while same and k < n do
    if out[k] ~= data[k] then same = false end
    k = k + 1
end

local hc = 0
for k = 0, csize - 1 do
    hc = (hc * 31 + comp[k]) % 1000003
end

local check = 0
if same then check = csize * 1000003 + hc end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

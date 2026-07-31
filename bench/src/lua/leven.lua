local DICT = 6000
local QUERIES = 40
local MAXLEN = 3

local floor = math.floor
local byte = string.byte

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

local function make_word(i)
    local n = i + 1
    local L = 4 + (i % 7)
    local out = {}
    for k = 0, L - 1 do
        out[k + 1] = string.char(97 + (n % 26))
        n = floor(n / 26) + 7 * k
    end
    return table.concat(out)
end

-- ---- data generation (not timed) ----
local words = {}
for i = 0, DICT - 1 do
    words[i + 1] = make_word(i)
end

local queries = {}
for q = 1, QUERIES do
    local src = words[(rnd() % DICT) + 1]
    local w = {}
    local nw = 0
    for i = 1, #src do
        nw = nw + 1
        w[nw] = string.sub(src, i, i)
    end
    for m = 1, 2 do
        local p = rnd() % nw
        local op = rnd() % 3
        local c = string.char(97 + (rnd() % 26))
        if op == 0 then
            w[p + 1] = c
        elseif op == 1 then
            if nw > 2 then
                table.remove(w, p + 1)
                nw = nw - 1
            end
        else
            table.insert(w, p + 1, c)
            nw = nw + 1
        end
    end
    queries[q] = table.concat(w)
end

-- ---- timed work ----
local t0 = os.clock()

local row0 = {}
local row1 = {}
for j = 0, 63 do row0[j] = 0; row1[j] = 0 end

local check = 0
for q = 1, QUERIES do
    local a = queries[q]
    local la = #a
    local best = 1073741824
    local bestIdx = -1
    for i = 1, DICT do
        local b = words[i]
        local lb = #b
        local d = la - lb
        if d < 0 then d = -d end
        if d <= MAXLEN then
            for j = 0, lb do row0[j] = j end
            for x = 0, la - 1 do
                row1[0] = x + 1
                local ca = byte(a, x + 1)
                for y = 0, lb - 1 do
                    local cost = (ca == byte(b, y + 1)) and 0 or 1
                    local v = row0[y] + cost
                    local v2 = row0[y + 1] + 1
                    if v2 < v then v = v2 end
                    v2 = row1[y] + 1
                    if v2 < v then v = v2 end
                    row1[y + 1] = v
                end
                for j = 0, lb do row0[j] = row1[j] end
            end
            local dd = row0[lb]
            if dd < best then
                best = dd
                bestIdx = i - 1
            end
        end
    end
    check = check + best * 31 + bestIdx
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

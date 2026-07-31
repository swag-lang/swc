local VOCAB = 5000
local WORDS = 2000000

local floor = math.floor
local byte = string.byte
local sub = string.sub

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

local function make_word(i)
    local n = i + 1
    local L = 3 + (i % 6)
    local out = {}
    for k = 0, L - 1 do
        out[k + 1] = string.char(97 + (n % 26))
        n = floor(n / 26) + 7 * k
    end
    return table.concat(out)
end

-- ---- data generation (not timed) ----
local vocab = {}
for i = 0, VOCAB - 1 do
    vocab[i + 1] = make_word(i)
end

local pieces = {}
local np = 0
for j = 0, WORDS - 1 do
    local idx = rnd() % VOCAB
    np = np + 1
    pieces[np] = vocab[idx + 1]
    np = np + 1
    pieces[np] = ((j + 1) % 12 == 0) and "\n" or " "
end
local text = table.concat(pieces)
pieces = nil

-- ---- timed work ----
local t0 = os.clock()

local counts = {}
local ndistinct = 0
local n = #text
local i = 1
local start = -1
while i <= n do
    local c = byte(text, i)
    if c >= 97 and c <= 122 then
        if start < 0 then start = i end
    else
        if start >= 0 then
            local tok = sub(text, start, i - 1)
            local v = counts[tok]
            if v == nil then
                counts[tok] = 1
                ndistinct = ndistinct + 1
            else
                counts[tok] = v + 1
            end
            start = -1
        end
    end
    i = i + 1
end
if start >= 0 then
    local tok = sub(text, start, n)
    local v = counts[tok]
    if v == nil then
        counts[tok] = 1
        ndistinct = ndistinct + 1
    else
        counts[tok] = v + 1
    end
end

local items = {}
local ni = 0
for w, c in pairs(counts) do
    ni = ni + 1
    items[ni] = { c, w }
end
table.sort(items, function(x, y)
    if x[1] ~= y[1] then return x[1] > y[1] end
    return x[2] < y[2]
end)

local check = ndistinct * 7
for k = 1, 20 do
    check = check + k * items[k][1]
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

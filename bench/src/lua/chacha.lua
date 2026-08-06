local SIZE = 262144 -- 32-bit words, one mebibyte of key stream

local U = 4294967296

-- bit-operation shim: LuaJIT/5.1 use the "bit" library, 5.4 uses native operators
local band, bor, bxor, lshift, rshift
local ok, bitlib = pcall(require, "bit")
if ok then
    band, bor, bxor = bitlib.band, bitlib.bor, bitlib.bxor
    lshift, rshift = bitlib.lshift, bitlib.rshift
else
    band = load("return function(a,b) return a & b end")()
    bor = load("return function(a,b) return a | b end")()
    bxor = load("return function(a,b) return a ~ b end")()
    lshift = load("return function(a,b) return (a << b) & 0xffffffff end")()
    rshift = load("return function(a,b) return (a & 0xffffffff) >> b end")()
end

local function ROL(x, k) return (lshift(x, k) % U + rshift(x, 32 - k) % U) % U end
local function XOR(a, b) return bxor(a, b) % U end

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

local function quarterRound(s, a, b, c, d)
    s[a] = (s[a] + s[b]) % U
    s[d] = XOR(s[d], s[a])
    s[d] = ROL(s[d], 16)
    s[c] = (s[c] + s[d]) % U
    s[b] = XOR(s[b], s[c])
    s[b] = ROL(s[b], 12)
    s[a] = (s[a] + s[b]) % U
    s[d] = XOR(s[d], s[a])
    s[d] = ROL(s[d], 8)
    s[c] = (s[c] + s[d]) % U
    s[b] = XOR(s[b], s[c])
    s[b] = ROL(s[b], 7)
end

-- ---- data generation (not timed) ----
local data = {}
for i = 1, SIZE do data[i] = rnd() % U end

local key = {}
for i = 1, 8 do key[i] = rnd() % U end

local nonce = {}
for i = 1, 3 do nonce[i] = rnd() % U end

-- ---- timed work ----
local t0 = os.clock()

-- one-based, so state word n of the specification lives at index n + 1
local initial = {}
initial[1] = 0x61707865
initial[2] = 0x3320646E
initial[3] = 0x79622D32
initial[4] = 0x6B206574
for i = 1, 8 do initial[4 + i] = key[i] end
for i = 1, 3 do initial[13 + i] = nonce[i] end

local state = {}
local offset = 0
local counter = 1
while offset < SIZE do
    initial[13] = counter

    for i = 1, 16 do state[i] = initial[i] end

    for _ = 1, 10 do
        quarterRound(state, 1, 5, 9, 13)
        quarterRound(state, 2, 6, 10, 14)
        quarterRound(state, 3, 7, 11, 15)
        quarterRound(state, 4, 8, 12, 16)
        quarterRound(state, 1, 6, 11, 16)
        quarterRound(state, 2, 7, 12, 13)
        quarterRound(state, 3, 8, 9, 14)
        quarterRound(state, 4, 5, 10, 15)
    end

    for i = 1, 16 do
        data[offset + i] = XOR(data[offset + i], (state[i] + initial[i]) % U)
    end

    offset = offset + 16
    counter = (counter + 1) % U
end

local check = 0
for i = 1, SIZE do
    check = XOR(check, (data[i] + i - 1) % U)
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

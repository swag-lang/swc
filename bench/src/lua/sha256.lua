local SIZE = 8388608

local floor = math.floor
local U = 4294967296

-- bit-operation shim: LuaJIT/5.1 use the "bit" library, 5.4 uses native operators
local band, bor, bxor, bnot, lshift, rshift
local ok, bitlib = pcall(require, "bit")
if ok then
    band, bor, bxor, bnot = bitlib.band, bitlib.bor, bitlib.bxor, bitlib.bnot
    lshift, rshift = bitlib.lshift, bitlib.rshift
else
    band = load("return function(a,b) return a & b end")()
    bor = load("return function(a,b) return a | b end")()
    bxor = load("return function(a,b) return a ~ b end")()
    bnot = load("return function(a) return ~a end")()
    lshift = load("return function(a,b) return (a << b) & 0xffffffff end")()
    rshift = load("return function(a,b) return (a & 0xffffffff) >> b end")()
end

local function XOR3(a, b, c) return bxor(bxor(a, b), c) % U end
local function ROTR(x, k) return (rshift(x, k) % U + lshift(x, 32 - k) % U) % U end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

-- ---- data generation (not timed) ----
local msg = {}
for i = 1, SIZE do
    msg[i] = rnd() % 256
end

-- ---- timed work ----
local t0 = os.clock()

local n = SIZE
local total_bits = n * 8
local buf = {}
for i = 1, n do buf[i] = msg[i] end
local nb = n + 1
buf[nb] = 0x80
while (nb % 64) ~= 56 do
    nb = nb + 1
    buf[nb] = 0
end
for s = 0, 7 do
    nb = nb + 1
    buf[nb] = floor(total_bits / (2 ^ (56 - 8 * s))) % 256
end

local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

local w = {}
local nblocks = nb / 64
for b = 0, nblocks - 1 do
    local o = b * 64
    for t = 0, 15 do
        local p = o + t * 4
        w[t] = buf[p + 1] * 16777216 + buf[p + 2] * 65536 + buf[p + 3] * 256 + buf[p + 4]
    end
    for t = 16, 63 do
        local x = w[t - 15]
        local y = w[t - 2]
        local s0 = XOR3(ROTR(x, 7), ROTR(x, 18), rshift(x, 3) % U)
        local s1 = XOR3(ROTR(y, 17), ROTR(y, 19), rshift(y, 10) % U)
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) % U
    end

    local a, bb, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for t = 0, 63 do
        local S1 = XOR3(ROTR(e, 6), ROTR(e, 11), ROTR(e, 25))
        local ch = bxor(band(e, f), band(bnot(e), g)) % U
        local t1 = (h + S1 + ch + K[t + 1] + w[t]) % U
        local S0 = XOR3(ROTR(a, 2), ROTR(a, 13), ROTR(a, 22))
        local maj = bxor(bxor(band(a, bb), band(a, c)), band(bb, c)) % U
        local t2 = (S0 + maj) % U
        h = g
        g = f
        f = e
        e = (d + t1) % U
        d = c
        c = bb
        bb = a
        a = (t1 + t2) % U
    end

    h0 = (h0 + a) % U
    h1 = (h1 + bb) % U
    h2 = (h2 + c) % U
    h3 = (h3 + d) % U
    h4 = (h4 + e) % U
    h5 = (h5 + f) % U
    h6 = (h6 + g) % U
    h7 = (h7 + h) % U
end

local check = bxor(bxor(bxor(h0, h1), bxor(h2, h3)), bxor(bxor(h4, h5), bxor(h6, h7))) % U

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

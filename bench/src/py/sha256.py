import time

SIZE = 524288

K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

# ---- data generation (not timed) ----
msg = bytearray(SIZE)
for i in range(SIZE):
    msg[i] = rnd() % 256

# ---- timed work ----
t0 = time.perf_counter()

M = 0xffffffff

def rotr(x, k):
    return ((x >> k) | (x << (32 - k))) & M

n = len(msg)
total_bits = n * 8
buf = bytearray(msg)
buf.append(0x80)
while (len(buf) % 64) != 56:
    buf.append(0)
for s in range(8):
    buf.append((total_bits >> (56 - 8 * s)) & 0xff)

h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

w = [0] * 64
nblocks = len(buf) // 64
for b in range(nblocks):
    o = b * 64
    for t in range(16):
        p = o + t * 4
        w[t] = (buf[p] << 24) | (buf[p + 1] << 16) | (buf[p + 2] << 8) | buf[p + 3]
    for t in range(16, 64):
        x = w[t - 15]
        y = w[t - 2]
        s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
        s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & M

    a, bb, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for t in range(64):
        S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        ch = (e & f) ^ ((~e & M) & g)
        t1 = (h + S1 + ch + K[t] + w[t]) & M
        S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        maj = (a & bb) ^ (a & c) ^ (bb & c)
        t2 = (S0 + maj) & M
        h = g
        g = f
        f = e
        e = (d + t1) & M
        d = c
        c = bb
        bb = a
        a = (t1 + t2) & M

    h0 = (h0 + a) & M
    h1 = (h1 + bb) & M
    h2 = (h2 + c) & M
    h3 = (h3 + d) & M
    h4 = (h4 + e) & M
    h5 = (h5 + f) & M
    h6 = (h6 + g) & M
    h7 = (h7 + h) & M

check = (h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7)

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

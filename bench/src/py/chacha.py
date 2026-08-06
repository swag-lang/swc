import time

SIZE = 262144  # 32-bit words, one mebibyte of key stream
M = 0xffffffff

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

def rol(x, k):
    return ((x << k) | (x >> (32 - k))) & M

# ---- data generation (not timed) ----
data = [rnd() & M for _ in range(SIZE)]
key = [rnd() & M for _ in range(8)]
nonce = [rnd() & M for _ in range(3)]

# ---- timed work ----
t0 = time.perf_counter()

initial = [0] * 16
initial[0] = 0x61707865
initial[1] = 0x3320646E
initial[2] = 0x79622D32
initial[3] = 0x6B206574
for i in range(8):
    initial[4 + i] = key[i]
for i in range(3):
    initial[13 + i] = nonce[i]

def quarter_round(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & M
    s[d] ^= s[a]
    s[d] = rol(s[d], 16)
    s[c] = (s[c] + s[d]) & M
    s[b] ^= s[c]
    s[b] = rol(s[b], 12)
    s[a] = (s[a] + s[b]) & M
    s[d] ^= s[a]
    s[d] = rol(s[d], 8)
    s[c] = (s[c] + s[d]) & M
    s[b] ^= s[c]
    s[b] = rol(s[b], 7)

offset = 0
counter = 1
while offset < SIZE:
    initial[12] = counter

    state = list(initial)
    for _ in range(10):
        quarter_round(state, 0, 4, 8, 12)
        quarter_round(state, 1, 5, 9, 13)
        quarter_round(state, 2, 6, 10, 14)
        quarter_round(state, 3, 7, 11, 15)
        quarter_round(state, 0, 5, 10, 15)
        quarter_round(state, 1, 6, 11, 12)
        quarter_round(state, 2, 7, 8, 13)
        quarter_round(state, 3, 4, 9, 14)

    for i in range(16):
        data[offset + i] ^= (state[i] + initial[i]) & M

    offset += 16
    counter = (counter + 1) & M

check = 0
for i in range(SIZE):
    check ^= (data[i] + i) & M

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

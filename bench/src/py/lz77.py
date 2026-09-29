import time

DATA_SIZE = 1 << 20
WORDS = 512
HASH_SIZE = 65536
WINDOW = 32768
MIN_MATCH = 4
MAX_MATCH = 258
MAX_CHAIN = 32

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

# ---- data generation (not timed) ----
words = []
for k in range(WORDS):
    length = 2 + rnd() % 8
    words.append([97 + rnd() % 26 for _ in range(length)])

n = DATA_SIZE
data = [0] * n
pos = 0
while pos < n:
    w = words[rnd() % WORDS]
    for b in w:
        if pos >= n:
            break
        data[pos] = b
        pos += 1
    if pos < n:
        data[pos] = 32
        pos += 1

# ---- timed work ----
t0 = time.perf_counter()

head = [-1] * HASH_SIZE
prev = [-1] * WINDOW

def hash_at(d, p):
    return (((d[p] * 33 + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE

comp = [0] * (n * 2 + 16)
csize = 0

i = 0
while i + MIN_MATCH <= n:
    best = 0
    dist = 0
    limit = n - i if n - i < MAX_MATCH else MAX_MATCH
    h = hash_at(data, i)
    cand = head[h]
    chain = 0
    while cand >= 0 and i - cand < WINDOW and chain < MAX_CHAIN:
        l = 0
        while l < limit and data[cand + l] == data[i + l]:
            l += 1
        if l > best:
            best = l
            dist = i - cand
            if l == limit:
                break
        cand = prev[cand % WINDOW]
        chain += 1

    prev[i % WINDOW] = head[h]
    head[h] = i

    if best >= MIN_MATCH:
        comp[csize] = 1
        comp[csize + 1] = best - MIN_MATCH
        comp[csize + 2] = (dist - 1) % 256
        comp[csize + 3] = (dist - 1) // 256
        csize += 4
        for p in range(i + 1, i + best):
            if p + MIN_MATCH <= n:
                hp = hash_at(data, p)
                prev[p % WINDOW] = head[hp]
                head[hp] = p
        i += best
    else:
        comp[csize] = 0
        comp[csize + 1] = data[i]
        csize += 2
        i += 1

while i < n:
    comp[csize] = 0
    comp[csize + 1] = data[i]
    csize += 2
    i += 1

# ---- decompress and verify ----
out = [0] * n
o = 0
c = 0
while c < csize:
    if comp[c] == 0:
        out[o] = comp[c + 1]
        o += 1
        c += 2
    else:
        length = comp[c + 1] + MIN_MATCH
        back = comp[c + 2] + comp[c + 3] * 256 + 1
        for k in range(length):
            out[o] = out[o - back]
            o += 1
        c += 4

same = o == n
k = 0
while same and k < n:
    if out[k] != data[k]:
        same = False
    k += 1

hc = 0
for k in range(csize):
    hc = (hc * 31 + comp[k]) % 1000003

check = csize * 1000003 + hc if same else 0

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

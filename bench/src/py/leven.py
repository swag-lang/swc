import time

DICT = 6000
QUERIES = 40
MAXLEN = 3

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

def make_word(i):
    n = i + 1
    L = 4 + (i % 7)
    out = []
    for k in range(L):
        out.append(chr(97 + (n % 26)))
        n = n // 26 + 7 * k
    return "".join(out)

# ---- data generation (not timed) ----
words = [make_word(i) for i in range(DICT)]

queries = []
for q in range(QUERIES):
    w = list(words[rnd() % DICT])
    for m in range(2):
        p = rnd() % len(w)
        op = rnd() % 3
        c = chr(97 + (rnd() % 26))
        if op == 0:
            w[p] = c
        elif op == 1:
            if len(w) > 2:
                del w[p]
        else:
            w.insert(p, c)
    queries.append("".join(w))

# ---- timed work ----
t0 = time.perf_counter()

row0 = [0] * 64
row1 = [0] * 64

check = 0
for q in range(QUERIES):
    a = queries[q]
    la = len(a)
    best = 1 << 30
    bestIdx = -1
    for i in range(DICT):
        b = words[i]
        lb = len(b)
        d = la - lb
        if d < 0:
            d = -d
        if d > MAXLEN:
            continue
        for j in range(lb + 1):
            row0[j] = j
        for x in range(la):
            row1[0] = x + 1
            ca = a[x]
            for y in range(lb):
                cost = 0 if ca == b[y] else 1
                v = row0[y] + cost
                v2 = row0[y + 1] + 1
                if v2 < v:
                    v = v2
                v2 = row1[y] + 1
                if v2 < v:
                    v = v2
                row1[y + 1] = v
            for j in range(lb + 1):
                row0[j] = row1[j]
        dd = row0[lb]
        if dd < best:
            best = dd
            bestIdx = i
    check += best * 31 + bestIdx

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

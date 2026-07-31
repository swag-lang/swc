import time, sys

VOCAB = 5000
WORDS = 2000000

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

def make_word(i):
    n = i + 1
    L = 3 + (i % 6)
    out = []
    for k in range(L):
        out.append(chr(97 + (n % 26)))
        n = n // 26 + 7 * k
    return "".join(out)

# ---- data generation (not timed) ----
vocab = [make_word(i) for i in range(VOCAB)]
pieces = []
for j in range(WORDS):
    idx = rnd() % VOCAB
    pieces.append(vocab[idx])
    pieces.append("\n" if (j + 1) % 12 == 0 else " ")
text = "".join(pieces).encode("ascii")

# ---- timed work ----
t0 = time.perf_counter()

counts = {}
n = len(text)
i = 0
start = -1
while i < n:
    c = text[i]
    if 97 <= c <= 122:
        if start < 0:
            start = i
    else:
        if start >= 0:
            tok = text[start:i]
            counts[tok] = counts.get(tok, 0) + 1
            start = -1
    i += 1
if start >= 0:
    tok = text[start:n]
    counts[tok] = counts.get(tok, 0) + 1

items = [(c, w) for w, c in counts.items()]
items.sort(key=lambda p: (-p[0], p[1]))

check = len(counts) * 7
for k in range(20):
    check += (k + 1) * items[k][0]

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

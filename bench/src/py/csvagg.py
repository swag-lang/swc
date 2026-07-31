import time

ROWS = 400000
REGIONS = ["EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"]

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

# ---- data generation (not timed) ----
lines = []
for j in range(ROWS):
    region = REGIONS[rnd() % 8]
    y = 2024 + (rnd() % 3)
    m = 1 + (rnd() % 12)
    d = 1 + (rnd() % 28)
    qty = 1 + (rnd() % 50)
    cents = 100 + (rnd() % 99900)
    lines.append("%d,%s,%d-%02d-%02d,%d,%d.%02d" % (j, region, y, m, d, qty, cents // 100, cents % 100))
text = "\n".join(lines).encode("ascii")

# ---- timed work ----
t0 = time.perf_counter()

n = len(text)
agg = {}
pos = 0
rows = 0
while pos < n:
    eol = pos
    while eol < n and text[eol] != 10:
        eol += 1

    # field 0: id
    p = pos
    while p < eol and text[p] != 44:
        p += 1
    p += 1

    # field 1: region
    rs = p
    while p < eol and text[p] != 44:
        p += 1
    region = text[rs:p]
    p += 1

    # field 2: date (skipped)
    while p < eol and text[p] != 44:
        p += 1
    p += 1

    # field 3: qty
    qty = 0
    while p < eol and text[p] != 44:
        qty = qty * 10 + (text[p] - 48)
        p += 1
    p += 1

    # field 4: price
    ip = 0
    while p < eol and text[p] != 46:
        ip = ip * 10 + (text[p] - 48)
        p += 1
    p += 1
    fr = 0
    while p < eol:
        fr = fr * 10 + (text[p] - 48)
        p += 1
    price = ip + fr / 100.0

    e = agg.get(region)
    if e is None:
        agg[region] = [1, qty, qty * price, price]
    else:
        e[0] += 1
        e[1] += qty
        e[2] += qty * price
        if price > e[3]:
            e[3] = price

    rows += 1
    pos = eol + 1

keys = sorted(agg.keys())
check = rows
for k in range(len(keys)):
    e = agg[keys[k]]
    check += (k + 1) * (int(e[2] * 100.0 + 0.5) % 1000003)
    check += e[0] + e[1] + int(e[3] * 100.0 + 0.5)

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

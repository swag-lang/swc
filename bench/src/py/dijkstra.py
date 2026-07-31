import time

N = 800
NN = N * N

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

# ---- data generation (not timed) ----
weight = [0] * NN
for i in range(NN):
    weight[i] = 1 + (rnd() % 9)

# ---- timed work ----
t0 = time.perf_counter()

INF = 1 << 60
dist = [INF] * NN

# hand-written binary heap of (dist, node) pairs, kept in two parallel arrays
hd = [0] * (NN * 4)
hn = [0] * (NN * 4)
hsize = 0

def push(d, node):
    global hsize
    i = hsize
    hsize += 1
    hd[i] = d
    hn[i] = node
    while i > 0:
        p = (i - 1) >> 1
        if hd[p] <= hd[i]:
            break
        hd[p], hd[i] = hd[i], hd[p]
        hn[p], hn[i] = hn[i], hn[p]
        i = p

def pop():
    global hsize
    rd = hd[0]
    rn = hn[0]
    hsize -= 1
    hd[0] = hd[hsize]
    hn[0] = hn[hsize]
    i = 0
    while True:
        l = 2 * i + 1
        if l >= hsize:
            break
        r = l + 1
        m = l
        if r < hsize and hd[r] < hd[l]:
            m = r
        if hd[i] <= hd[m]:
            break
        hd[m], hd[i] = hd[i], hd[m]
        hn[m], hn[i] = hn[i], hn[m]
        i = m
    return rd, rn

dist[0] = 0
push(0, 0)
pops = 0
target = NN - 1

while hsize > 0:
    d, u = pop()
    pops += 1
    if d > dist[u]:
        continue
    if u == target:
        break
    x = u % N
    y = u // N
    if x > 0:
        v = u - 1
        nd = d + weight[v]
        if nd < dist[v]:
            dist[v] = nd
            push(nd, v)
    if x < N - 1:
        v = u + 1
        nd = d + weight[v]
        if nd < dist[v]:
            dist[v] = nd
            push(nd, v)
    if y > 0:
        v = u - N
        nd = d + weight[v]
        if nd < dist[v]:
            dist[v] = nd
            push(nd, v)
    if y < N - 1:
        v = u + N
        nd = d + weight[v]
        if nd < dist[v]:
            dist[v] = nd
            push(nd, v)

check = dist[target] * 1000 + (pops % 1000)

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

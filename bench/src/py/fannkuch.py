import time

N = 9

# ---- data generation (not timed) ----
perm = [0] * N
perm1 = [0] * N
count = [0] * N

# ---- timed work ----
t0 = time.perf_counter()

for i in range(N):
    perm1[i] = i

checksum = 0
max_flips = 0
perm_count = 0
r = N

while True:
    while r != 1:
        count[r - 1] = r
        r -= 1

    for i in range(N):
        perm[i] = perm1[i]

    flips = 0
    k = perm[0]
    while k != 0:
        i = 0
        j = k
        while i < j:
            perm[i], perm[j] = perm[j], perm[i]
            i += 1
            j -= 1
        flips += 1
        k = perm[0]

    if flips > max_flips:
        max_flips = flips
    if perm_count % 2 == 0:
        checksum += flips
    else:
        checksum -= flips

    # rotate the prefix to reach the next permutation
    done = False
    while True:
        if r == N:
            done = True
            break
        perm0 = perm1[0]
        for i in range(r):
            perm1[i] = perm1[i + 1]
        perm1[r] = perm0
        count[r] -= 1
        if count[r] > 0:
            break
        r += 1
    if done:
        break
    perm_count += 1

check = checksum * 1000 + max_flips

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

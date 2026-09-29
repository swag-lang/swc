import time

N = 300000

seed = 12345
def rnd():
    global seed
    seed = (seed * 16807) % 2147483647
    return seed

def qsort(a, lo, hi):
    while hi - lo > 16:
        mid = lo + (hi - lo) // 2
        if a[mid] < a[lo]:
            a[lo], a[mid] = a[mid], a[lo]
        if a[hi] < a[lo]:
            a[lo], a[hi] = a[hi], a[lo]
        if a[hi] < a[mid]:
            a[mid], a[hi] = a[hi], a[mid]

        pivot = a[mid]
        i = lo
        j = hi
        while True:
            while a[i] < pivot:
                i += 1
            while a[j] > pivot:
                j -= 1
            if i <= j:
                a[i], a[j] = a[j], a[i]
                i += 1
                j -= 1
            if i > j:
                break

        # recurse into the smaller side, loop on the larger one
        if j - lo < hi - i:
            qsort(a, lo, j)
            lo = i
        else:
            qsort(a, i, hi)
            hi = j

    for i in range(lo + 1, hi + 1):
        v = a[i]
        j = i - 1
        while j >= lo and a[j] > v:
            a[j + 1] = a[j]
            j -= 1
        a[j + 1] = v

# ---- data generation (not timed) ----
a = [0] * N
for i in range(N):
    a[i] = rnd()

# ---- timed work ----
t0 = time.perf_counter()

qsort(a, 0, N - 1)

is_sorted = True
for i in range(1, N):
    if a[i - 1] > a[i]:
        is_sorted = False

check = 0
if is_sorted:
    for i in range(N):
        check += (a[i] % 1000) * (i % 7 + 1)

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (check, (t1 - t0) * 1000.0))

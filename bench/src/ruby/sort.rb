N = 300000
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

def qsort(a, lo, hi)
  while ((hi - lo) > 16)
    mid = (lo + ((hi - lo) / 2))
    if (a[mid] < a[lo])
      a[lo], a[mid] = a[mid], a[lo]
    end
    if (a[hi] < a[lo])
      a[lo], a[hi] = a[hi], a[lo]
    end
    if (a[hi] < a[mid])
      a[mid], a[hi] = a[hi], a[mid]
    end
    pivot = a[mid]
    i = lo
    j = hi
    while true
      while (a[i] < pivot)
        i += 1
      end
      while (a[j] > pivot)
        j -= 1
      end
      if (i <= j)
        a[i], a[j] = a[j], a[i]
        i += 1
        j -= 1
      end
      if (i > j)
        break
      end
    end
    if ((j - lo) < (hi - i))
      qsort(a, lo, j)
      lo = i
    else
      qsort(a, i, hi)
      hi = j
    end
  end
  ((lo + 1)).step(((hi + 1)) - 1, 1) do |i|
    v = a[i]
    j = (i - 1)
    while ((j >= lo) && (a[j] > v))
      a[(j + 1)] = a[j]
      j -= 1
    end
    a[(j + 1)] = v
  end
end

a = Array.new(N, 0)
(0).step((N) - 1, 1) do |i|
  a[i] = rnd()
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
qsort(a, 0, (N - 1))
is_sorted = true
(1).step((N) - 1, 1) do |i|
  if (a[(i - 1)] > a[i])
    is_sorted = false
  end
end
check = 0
if is_sorted
  (0).step((N) - 1, 1) do |i|
    check += ((a[i] % 1000) * ((i % 7) + 1))
  end
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

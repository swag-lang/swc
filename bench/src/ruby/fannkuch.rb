N = 9
perm = Array.new(N, 0)
perm1 = Array.new(N, 0)
count = Array.new(N, 0)

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
(0).step((N) - 1, 1) do |i|
  perm1[i] = i
end
checksum = 0
max_flips = 0
perm_count = 0
r = N
while true
  while (r != 1)
    count[(r - 1)] = r
    r -= 1
  end
  (0).step((N) - 1, 1) do |i|
    perm[i] = perm1[i]
  end
  flips = 0
  k = perm[0]
  while (k != 0)
    i = 0
    j = k
    while (i < j)
      perm[i], perm[j] = perm[j], perm[i]
      i += 1
      j -= 1
    end
    flips += 1
    k = perm[0]
  end
  if (flips > max_flips)
    max_flips = flips
  end
  if ((perm_count % 2) == 0)
    checksum += flips
  else
    checksum -= flips
  end
  done = false
  while true
    if (r == N)
      done = true
      break
    end
    perm0 = perm1[0]
    (0).step((r) - 1, 1) do |i|
      perm1[i] = perm1[(i + 1)]
    end
    perm1[r] = perm0
    count[r] -= 1
    if (count[r] > 0)
      break
    end
    r += 1
  end
  if done
    break
  end
  perm_count += 1
end
check = ((checksum * 1000) + max_flips)
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

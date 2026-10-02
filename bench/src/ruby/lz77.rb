DATA_SIZE = (1 << 20)
WORDS = 512
HASH_SIZE = 65536
WINDOW = 32768
MIN_MATCH = 4
MAX_MATCH = 258
MAX_CHAIN = 32
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

words = []
(0).step((WORDS) - 1, 1) do |k|
  length = (2 + (rnd() % 8))
  words << Array.new(length) { (97 + (rnd() % 26)) }
end
n = DATA_SIZE
data = Array.new(n, 0)
pos = 0
while (pos < n)
  w = words[(rnd() % WORDS)]
  w.each do |b|
    if (pos >= n)
      break
    end
    data[pos] = b
    pos += 1
  end
  if (pos < n)
    data[pos] = 32
    pos += 1
  end
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
head = Array.new(HASH_SIZE, (-1))
prev = Array.new(WINDOW, (-1))

def hash_at(d, p)
  return (((((((d[p] * 33) + d[(p + 1)]) * 33) + d[(p + 2)]) * 33) + d[(p + 3)]) % HASH_SIZE)
end

comp = Array.new(((n * 2) + 16), 0)
csize = 0
i = 0
while ((i + MIN_MATCH) <= n)
  best = 0
  dist = 0
  limit = (((n - i) < MAX_MATCH) ? (n - i) : MAX_MATCH)
  h = hash_at(data, i)
  cand = head[h]
  chain = 0
  while ((cand >= 0) && ((i - cand) < WINDOW) && (chain < MAX_CHAIN))
    l = 0
    while ((l < limit) && (data[(cand + l)] == data[(i + l)]))
      l += 1
    end
    if (l > best)
      best = l
      dist = (i - cand)
      if (l == limit)
        break
      end
    end
    cand = prev[(cand % WINDOW)]
    chain += 1
  end
  prev[(i % WINDOW)] = head[h]
  head[h] = i
  if (best >= MIN_MATCH)
    comp[csize] = 1
    comp[(csize + 1)] = (best - MIN_MATCH)
    comp[(csize + 2)] = ((dist - 1) % 256)
    comp[(csize + 3)] = ((dist - 1) / 256)
    csize += 4
    ((i + 1)).step(((i + best)) - 1, 1) do |p|
      if ((p + MIN_MATCH) <= n)
        hp = hash_at(data, p)
        prev[(p % WINDOW)] = head[hp]
        head[hp] = p
      end
    end
    i += best
  else
    comp[csize] = 0
    comp[(csize + 1)] = data[i]
    csize += 2
    i += 1
  end
end
while (i < n)
  comp[csize] = 0
  comp[(csize + 1)] = data[i]
  csize += 2
  i += 1
end
out = Array.new(n, 0)
o = 0
c = 0
while (c < csize)
  if (comp[c] == 0)
    out[o] = comp[(c + 1)]
    o += 1
    c += 2
  else
    length = (comp[(c + 1)] + MIN_MATCH)
    back = ((comp[(c + 2)] + (comp[(c + 3)] * 256)) + 1)
    (0).step((length) - 1, 1) do |k|
      out[o] = out[(o - back)]
      o += 1
    end
    c += 4
  end
end
same = (o == n)
k = 0
while (same && (k < n))
  if (out[k] != data[k])
    same = false
  end
  k += 1
end
hc = 0
(0).step((csize) - 1, 1) do |k|
  hc = (((hc * 31) + comp[k]) % 1000003)
end
check = (same ? ((csize * 1000003) + hc) : 0)
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

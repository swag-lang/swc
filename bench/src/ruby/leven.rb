DICT = 6000
QUERIES = 40
MAXLEN = 3
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

def make_word(i)
  n = (i + 1)
  length = (4 + (i % 7))
  out = []
  (0).step((length) - 1, 1) do |k|
    out << ((97 + (n % 26))).chr
    n = ((n / 26) + (7 * k))
  end
  return out.join("")
end

words = []
(0).step((DICT) - 1, 1) do |i|
  words << make_word(i)
end
queries = []
(0).step((QUERIES) - 1, 1) do |q|
  w = words[(rnd() % DICT)].chars
  (0).step((2) - 1, 1) do |m|
    p = (rnd() % w.length)
    op = (rnd() % 3)
    c = ((97 + (rnd() % 26))).chr
    if (op == 0)
      w[p] = c
    else
      if (op == 1)
        if (w.length > 2)
          w.delete_at(p)
        end
      else
        w.insert(p, c)
      end
    end
  end
  queries << w.join("")
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
row0 = Array.new(64, 0)
row1 = Array.new(64, 0)
check = 0
(0).step((QUERIES) - 1, 1) do |q|
  a = queries[q]
  la = a.length
  best = (1 << 30)
  bestIdx = (-1)
  (0).step((DICT) - 1, 1) do |i|
    b = words[i]
    lb = b.length
    d = (la - lb)
    if (d < 0)
      d = (-d)
    end
    if (d > MAXLEN)
      next
    end
    (0).step(((lb + 1)) - 1, 1) do |j|
      row0[j] = j
    end
    (0).step((la) - 1, 1) do |x|
      row1[0] = (x + 1)
      ca = a[x]
      (0).step((lb) - 1, 1) do |y|
        cost = ((ca == b[y]) ? 0 : 1)
        v = (row0[y] + cost)
        v2 = (row0[(y + 1)] + 1)
        if (v2 < v)
          v = v2
        end
        v2 = (row1[y] + 1)
        if (v2 < v)
          v = v2
        end
        row1[(y + 1)] = v
      end
      (0).step(((lb + 1)) - 1, 1) do |j|
        row0[j] = row1[j]
      end
    end
    dd = row0[lb]
    if (dd < best)
      best = dd
      bestIdx = i
    end
  end
  check += ((best * 31) + bestIdx)
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

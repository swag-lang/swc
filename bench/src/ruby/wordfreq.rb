VOCAB = 5000
WORDS = 2000000
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

def make_word(i)
  n = (i + 1)
  length = (3 + (i % 6))
  out = []
  (0).step((length) - 1, 1) do |k|
    out << ((97 + (n % 26))).chr
    n = ((n / 26) + (7 * k))
  end
  return out.join("")
end

vocab = []
(0).step((VOCAB) - 1, 1) do |i|
  vocab << make_word(i)
end
pieces = []
(0).step((WORDS) - 1, 1) do |j|
  idx = (rnd() % VOCAB)
  pieces << vocab[idx]
  pieces << ((((j + 1) % 12) == 0) ? "\n" : " ")
end
text = pieces.join("").bytes

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
counts = {}
n = text.length
i = 0
start = (-1)
while (i < n)
  c = text[i]
  if (97 <= c && c <= 122)
    if (start < 0)
      start = i
    end
  else
    if (start >= 0)
      tok = text[start...i]
      counts[tok] = (counts.fetch(tok, 0) + 1)
      start = (-1)
    end
  end
  i += 1
end
if (start >= 0)
  tok = text[start...n]
  counts[tok] = (counts.fetch(tok, 0) + 1)
end
items = []
counts.each do |w, c|
  items << [c, w]
end
items.sort_by! { |p| [-p[0], p[1]] }
check = (counts.length * 7)
(0).step((20) - 1, 1) do |k|
  check += ((k + 1) * items[k][0])
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

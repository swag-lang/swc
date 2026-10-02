SIZE = 4194304
M = 0xffffffff
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

def rol(x, k)
  return (((x << k) | (x >> (32 - k))) & M)
end

data = []
(0).step((SIZE) - 1, 1) do |_|
  data << (rnd() & M)
end
key = []
(0).step((8) - 1, 1) do |_|
  key << (rnd() & M)
end
nonce = []
(0).step((3) - 1, 1) do |_|
  nonce << (rnd() & M)
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
initial = Array.new(16, 0)
initial[0] = 0x61707865
initial[1] = 0x3320646E
initial[2] = 0x79622D32
initial[3] = 0x6B206574
(0).step((8) - 1, 1) do |i|
  initial[(4 + i)] = key[i]
end
(0).step((3) - 1, 1) do |i|
  initial[(13 + i)] = nonce[i]
end

def quarter_round(s, a, b, c, d)
  s[a] = ((s[a] + s[b]) & M)
  s[d] ^= s[a]
  s[d] = rol(s[d], 16)
  s[c] = ((s[c] + s[d]) & M)
  s[b] ^= s[c]
  s[b] = rol(s[b], 12)
  s[a] = ((s[a] + s[b]) & M)
  s[d] ^= s[a]
  s[d] = rol(s[d], 8)
  s[c] = ((s[c] + s[d]) & M)
  s[b] ^= s[c]
  s[b] = rol(s[b], 7)
end

offset = 0
counter = 1
while (offset < SIZE)
  initial[12] = counter
  state = initial.dup
  (0).step((10) - 1, 1) do |_|
    quarter_round(state, 0, 4, 8, 12)
    quarter_round(state, 1, 5, 9, 13)
    quarter_round(state, 2, 6, 10, 14)
    quarter_round(state, 3, 7, 11, 15)
    quarter_round(state, 0, 5, 10, 15)
    quarter_round(state, 1, 6, 11, 12)
    quarter_round(state, 2, 7, 8, 13)
    quarter_round(state, 3, 4, 9, 14)
  end
  (0).step((16) - 1, 1) do |i|
    data[(offset + i)] ^= ((state[i] + initial[i]) & M)
  end
  offset += 16
  counter = ((counter + 1) & M)
end
check = 0
(0).step((SIZE) - 1, 1) do |i|
  check ^= ((data[i] + i) & M)
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

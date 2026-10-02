ROWS = 400000
REGIONS = ["EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"]
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

lines = []
(0).step((ROWS) - 1, 1) do |j|
  region = REGIONS[(rnd() % 8)]
  y = (2024 + (rnd() % 3))
  m = (1 + (rnd() % 12))
  d = (1 + (rnd() % 28))
  qty = (1 + (rnd() % 50))
  cents = (100 + (rnd() % 99900))
  lines << format("%d,%s,%d-%02d-%02d,%d,%d.%02d", j, region, y, m, d, qty, (cents / 100), (cents % 100))
end
text = lines.join("\n").bytes

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
n = text.length
agg = {}
pos = 0
rows = 0
while (pos < n)
  eol = pos
  while ((eol < n) && (text[eol] != 10))
    eol += 1
  end
  p = pos
  while ((p < eol) && (text[p] != 44))
    p += 1
  end
  p += 1
  rs = p
  while ((p < eol) && (text[p] != 44))
    p += 1
  end
  region = text[rs...p]
  p += 1
  while ((p < eol) && (text[p] != 44))
    p += 1
  end
  p += 1
  qty = 0
  while ((p < eol) && (text[p] != 44))
    qty = ((qty * 10) + (text[p] - 48))
    p += 1
  end
  p += 1
  ip = 0
  while ((p < eol) && (text[p] != 46))
    ip = ((ip * 10) + (text[p] - 48))
    p += 1
  end
  p += 1
  fr = 0
  while (p < eol)
    fr = ((fr * 10) + (text[p] - 48))
    p += 1
  end
  price = (ip + (fr / 100.0))
  e = agg.fetch(region, nil)
  if (e == nil)
    agg[region] = [1, qty, (qty * price), price]
  else
    e[0] += 1
    e[1] += qty
    e[2] += (qty * price)
    if (price > e[3])
      e[3] = price
    end
  end
  rows += 1
  pos = (eol + 1)
end
keys = agg.keys.sort
check = rows
(0).step((keys.length) - 1, 1) do |k|
  e = agg[keys[k]]
  check += ((k + 1) * ((((e[2] * 100.0) + 0.5)).to_i % 1000003))
  check += ((e[0] + e[1]) + (((e[3] * 100.0) + 0.5)).to_i)
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

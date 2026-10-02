N = 800
NN = (N * N)
$seed = 12345

def rnd()
  $seed = (($seed * 16807) % 2147483647)
  return $seed
end

weight = Array.new(NN, 0)
(0).step((NN) - 1, 1) do |i|
  weight[i] = (1 + (rnd() % 9))
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
INF = (1 << 60)
dist = Array.new(NN, INF)
$hd = Array.new((NN * 4), 0)
$hn = Array.new((NN * 4), 0)
$hsize = 0

def push(d, node)
  i = $hsize
  $hsize += 1
  $hd[i] = d
  $hn[i] = node
  while (i > 0)
    p = ((i - 1) >> 1)
    if ($hd[p] <= $hd[i])
      break
    end
    $hd[p], $hd[i] = $hd[i], $hd[p]
    $hn[p], $hn[i] = $hn[i], $hn[p]
    i = p
  end
end

def pop()
  rd = $hd[0]
  rn = $hn[0]
  $hsize -= 1
  $hd[0] = $hd[$hsize]
  $hn[0] = $hn[$hsize]
  i = 0
  while true
    l = ((2 * i) + 1)
    if (l >= $hsize)
      break
    end
    r = (l + 1)
    m = l
    if ((r < $hsize) && ($hd[r] < $hd[l]))
      m = r
    end
    if ($hd[i] <= $hd[m])
      break
    end
    $hd[m], $hd[i] = $hd[i], $hd[m]
    $hn[m], $hn[i] = $hn[i], $hn[m]
    i = m
  end
  return rd, rn
end

dist[0] = 0
push(0, 0)
pops = 0
target = (NN - 1)
while ($hsize > 0)
  d, u = pop()
  pops += 1
  if (d > dist[u])
    next
  end
  if (u == target)
    break
  end
  x = (u % N)
  y = (u / N)
  if (x > 0)
    v = (u - 1)
    nd = (d + weight[v])
    if (nd < dist[v])
      dist[v] = nd
      push(nd, v)
    end
  end
  if (x < (N - 1))
    v = (u + 1)
    nd = (d + weight[v])
    if (nd < dist[v])
      dist[v] = nd
      push(nd, v)
    end
  end
  if (y > 0)
    v = (u - N)
    nd = (d + weight[v])
    if (nd < dist[v])
      dist[v] = nd
      push(nd, v)
    end
  end
  if (y < (N - 1))
    v = (u + N)
    nd = (d + weight[v])
    if (nd < dist[v])
      dist[v] = nd
      push(nd, v)
    end
  end
end
check = ((dist[target] * 1000) + (pops % 1000))
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

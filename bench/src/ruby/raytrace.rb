W = 480
H = 360
NS = 4
$scx = [0.0, 2.0, (-2.0), 0.0]
$scy = [(-0.5), 0.0, 0.0, (-5001.0)]
$scz = [3.0, 4.5, 4.0, 0.0]
$srad = [1.0, 1.0, 1.0, 5000.0]
$sr = [1.0, 0.2, 0.2, 0.9]
$sg = [0.25, 1.0, 0.3, 0.85]
$sb = [0.25, 0.3, 1.0, 0.3]
$sre = [0.35, 0.45, 0.55, 0.15]
LX = 5.0
LY = 5.0
LZ = (-3.0)
AMB = 0.12

def intersect(ox, oy, oz, dx, dy, dz, tmin)
  best = 1e30
  hit = (-1)
  (0).step((NS) - 1, 1) do |i|
    ex = (ox - $scx[i])
    ey = (oy - $scy[i])
    ez = (oz - $scz[i])
    b = (2.0 * (((ex * dx) + (ey * dy)) + (ez * dz)))
    c = ((((ex * ex) + (ey * ey)) + (ez * ez)) - ($srad[i] * $srad[i]))
    disc = ((b * b) - (4.0 * c))
    if (disc < 0.0)
      next
    end
    sq = Math.sqrt(disc)
    t = (((-b) - sq) * 0.5)
    if (t < tmin)
      t = (((-b) + sq) * 0.5)
    end
    if ((t >= tmin) && (t < best))
      best = t
      hit = i
    end
  end
  return best, hit
end

def trace(ox, oy, oz, dx, dy, dz, depth)
  t, hit = intersect(ox, oy, oz, dx, dy, dz, 0.0001)
  if (hit < 0)
    return 0.05, 0.07, 0.12
  end
  px = (ox + (dx * t))
  py = (oy + (dy * t))
  pz = (oz + (dz * t))
  nx = (px - $scx[hit])
  ny = (py - $scy[hit])
  nz = (pz - $scz[hit])
  nl = (1.0 / $srad[hit])
  nx *= nl
  ny *= nl
  nz *= nl
  lx = (LX - px)
  ly = (LY - py)
  lz = (LZ - pz)
  ll = (1.0 / Math.sqrt((((lx * lx) + (ly * ly)) + (lz * lz))))
  lx *= ll
  ly *= ll
  lz *= ll
  lam = (((nx * lx) + (ny * ly)) + (nz * lz))
  if (lam < 0.0)
    lam = 0.0
  else
    st, sh = intersect(px, py, pz, lx, ly, lz, 0.001)
    if (sh >= 0)
      lam = 0.0
    end
  end
  k = (AMB + (0.88 * lam))
  cr = ($sr[hit] * k)
  cg = ($sg[hit] * k)
  cb = ($sb[hit] * k)
  refl = $sre[hit]
  if ((refl > 0.0) && (depth < 2))
    d = (2.0 * (((dx * nx) + (dy * ny)) + (dz * nz)))
    rx = (dx - (d * nx))
    ry = (dy - (d * ny))
    rz = (dz - (d * nz))
    rr, rg, rb = trace(px, py, pz, rx, ry, rz, (depth + 1))
    cr = ((cr * (1.0 - refl)) + (rr * refl))
    cg = ((cg * (1.0 - refl)) + (rg * refl))
    cb = ((cb * (1.0 - refl)) + (rb * refl))
  end
  return cr, cg, cb
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
aspect = ((W).to_f / (H).to_f)
check = 0
(0).step((H) - 1, 1) do |py|
  (0).step((W) - 1, 1) do |px|
    dx = (((((px + 0.5) / W) * 2.0) - 1.0) * aspect)
    dy = (1.0 - (((py + 0.5) / H) * 2.0))
    dz = 1.0
    il = (1.0 / Math.sqrt((((dx * dx) + (dy * dy)) + (dz * dz))))
    cr, cg, cb = trace(0.0, 0.0, 0.0, (dx * il), (dy * il), (dz * il), 0)
    ir = ((cr * 255.0)).to_i
    ig = ((cg * 255.0)).to_i
    ib = ((cb * 255.0)).to_i
    if (ir > 255)
      ir = 255
    end
    if (ig > 255)
      ig = 255
    end
    if (ib > 255)
      ib = 255
    end
    check += ((ir + (2 * ig)) + (3 * ib))
  end
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

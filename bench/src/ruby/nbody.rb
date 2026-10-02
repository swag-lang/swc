STEPS = 500000
PI = 3.141592653589793
SOLAR_MASS = ((4.0 * PI) * PI)
DAYS_PER_YEAR = 365.24
class Body
  attr_accessor :x, :y, :z, :vx, :vy, :vz, :mass

  def initialize(x, y, z, vx, vy, vz, mass)
    @x = x
    @y = y
    @z = z
    @vx = vx
    @vy = vy
    @vz = vz
    @mass = mass
  end

end

def offset_momentum(bodies)
  px = 0.0
  py = 0.0
  pz = 0.0
  bodies.each do |b|
    px += (b.vx * b.mass)
    py += (b.vy * b.mass)
    pz += (b.vz * b.mass)
  end
  bodies[0].vx = ((-px) / SOLAR_MASS)
  bodies[0].vy = ((-py) / SOLAR_MASS)
  bodies[0].vz = ((-pz) / SOLAR_MASS)
end

def advance(bodies, dt)
  nb = bodies.length
  (0).step((nb) - 1, 1) do |i|
    bi = bodies[i]
    ((i + 1)).step((nb) - 1, 1) do |j|
      bj = bodies[j]
      dx = (bi.x - bj.x)
      dy = (bi.y - bj.y)
      dz = (bi.z - bj.z)
      d2 = (((dx * dx) + (dy * dy)) + (dz * dz))
      mag = (dt / (d2 * Math.sqrt(d2)))
      bi.vx -= ((dx * bj.mass) * mag)
      bi.vy -= ((dy * bj.mass) * mag)
      bi.vz -= ((dz * bj.mass) * mag)
      bj.vx += ((dx * bi.mass) * mag)
      bj.vy += ((dy * bi.mass) * mag)
      bj.vz += ((dz * bi.mass) * mag)
    end
  end
  bodies.each do |b|
    b.x += (dt * b.vx)
    b.y += (dt * b.vy)
    b.z += (dt * b.vz)
  end
end

def energy(bodies)
  e = 0.0
  nb = bodies.length
  (0).step((nb) - 1, 1) do |i|
    bi = bodies[i]
    e += ((0.5 * bi.mass) * (((bi.vx * bi.vx) + (bi.vy * bi.vy)) + (bi.vz * bi.vz)))
    ((i + 1)).step((nb) - 1, 1) do |j|
      bj = bodies[j]
      dx = (bi.x - bj.x)
      dy = (bi.y - bj.y)
      dz = (bi.z - bj.z)
      e -= ((bi.mass * bj.mass) / Math.sqrt((((dx * dx) + (dy * dy)) + (dz * dz))))
    end
  end
  return e
end

bodies = [Body.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS), Body.new(4.84143144246472090e+00, (-1.16032004402742839e+00), (-1.03622044471123109e-01), (1.66007664274403694e-03 * DAYS_PER_YEAR), (7.69901118419740425e-03 * DAYS_PER_YEAR), ((-6.90460016972063023e-05) * DAYS_PER_YEAR), (9.54791938424326609e-04 * SOLAR_MASS)), Body.new(8.34336671824457987e+00, 4.12479856412430479e+00, (-4.03523417114321381e-01), ((-2.76742510726862411e-03) * DAYS_PER_YEAR), (4.99852801234917238e-03 * DAYS_PER_YEAR), (2.30417297573763929e-05 * DAYS_PER_YEAR), (2.85885980666130812e-04 * SOLAR_MASS)), Body.new(1.28943695621391310e+01, (-1.51111514016986312e+01), (-2.23307578892655734e-01), (2.96460137564761618e-03 * DAYS_PER_YEAR), (2.37847173959480950e-03 * DAYS_PER_YEAR), ((-2.96589568540237556e-05) * DAYS_PER_YEAR), (4.36624404335156298e-05 * SOLAR_MASS)), Body.new(1.53796971148509165e+01, (-2.59193146099879641e+01), 1.79258772950371181e-01, (2.68067772490389322e-03 * DAYS_PER_YEAR), (1.62824170038242295e-03 * DAYS_PER_YEAR), ((-9.51592254519715870e-05) * DAYS_PER_YEAR), (5.15138902046611451e-05 * SOLAR_MASS))]

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
offset_momentum(bodies)
(0).step((STEPS) - 1, 1) do |s|
  advance(bodies, 0.01)
end
e = energy(bodies)
check = (((-e) * 1e12)).floor
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", check, ((t1 - t0) * 1000.0))

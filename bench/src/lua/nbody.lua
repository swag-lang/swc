local STEPS = 500000
local PI = 3.141592653589793
local SOLAR_MASS = 4.0 * PI * PI
local DAYS_PER_YEAR = 365.24

local sqrt = math.sqrt
local floor = math.floor

local function body(x, y, z, vx, vy, vz, mass)
    return { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, mass = mass }
end

local function offsetMomentum(bodies, nb)
    local px, py, pz = 0.0, 0.0, 0.0
    for i = 1, nb do
        local b = bodies[i]
        px = px + b.vx * b.mass
        py = py + b.vy * b.mass
        pz = pz + b.vz * b.mass
    end
    bodies[1].vx = -px / SOLAR_MASS
    bodies[1].vy = -py / SOLAR_MASS
    bodies[1].vz = -pz / SOLAR_MASS
end

local function advance(bodies, nb, dt)
    for i = 1, nb do
        local bi = bodies[i]
        for j = i + 1, nb do
            local bj = bodies[j]
            local dx = bi.x - bj.x
            local dy = bi.y - bj.y
            local dz = bi.z - bj.z
            local d2 = dx * dx + dy * dy + dz * dz
            local mag = dt / (d2 * sqrt(d2))
            bi.vx = bi.vx - dx * bj.mass * mag
            bi.vy = bi.vy - dy * bj.mass * mag
            bi.vz = bi.vz - dz * bj.mass * mag
            bj.vx = bj.vx + dx * bi.mass * mag
            bj.vy = bj.vy + dy * bi.mass * mag
            bj.vz = bj.vz + dz * bi.mass * mag
        end
    end
    for i = 1, nb do
        local b = bodies[i]
        b.x = b.x + dt * b.vx
        b.y = b.y + dt * b.vy
        b.z = b.z + dt * b.vz
    end
end

local function energy(bodies, nb)
    local e = 0.0
    for i = 1, nb do
        local bi = bodies[i]
        e = e + 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
        for j = i + 1, nb do
            local bj = bodies[j]
            local dx = bi.x - bj.x
            local dy = bi.y - bj.y
            local dz = bi.z - bj.z
            e = e - (bi.mass * bj.mass) / sqrt(dx * dx + dy * dy + dz * dz)
        end
    end
    return e
end

-- ---- data generation (not timed) ----
local bodies = {
    -- sun
    body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS),
    -- jupiter
    body(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
         1.66007664274403694e-03 * DAYS_PER_YEAR, 7.69901118419740425e-03 * DAYS_PER_YEAR,
         -6.90460016972063023e-05 * DAYS_PER_YEAR, 9.54791938424326609e-04 * SOLAR_MASS),
    -- saturn
    body(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
         -2.76742510726862411e-03 * DAYS_PER_YEAR, 4.99852801234917238e-03 * DAYS_PER_YEAR,
         2.30417297573763929e-05 * DAYS_PER_YEAR, 2.85885980666130812e-04 * SOLAR_MASS),
    -- uranus
    body(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
         2.96460137564761618e-03 * DAYS_PER_YEAR, 2.37847173959480950e-03 * DAYS_PER_YEAR,
         -2.96589568540237556e-05 * DAYS_PER_YEAR, 4.36624404335156298e-05 * SOLAR_MASS),
    -- neptune
    body(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
         2.68067772490389322e-03 * DAYS_PER_YEAR, 1.62824170038242295e-03 * DAYS_PER_YEAR,
         -9.51592254519715870e-05 * DAYS_PER_YEAR, 5.15138902046611451e-05 * SOLAR_MASS),
}
local nb = #bodies

-- ---- timed work ----
local t0 = os.clock()

offsetMomentum(bodies, nb)
for s = 1, STEPS do
    advance(bodies, nb, 0.01)
end
local e = energy(bodies, nb)

local check = floor(-e * 1e12)

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))

const STEPS         = 500000
const NB            = 5
const PI            = 3.141592653589793'f64
const SOLAR_MASS    = 4.0'f64 * PI * PI
const DAYS_PER_YEAR = 365.24'f64

struct Body
{
    x, y, z:    f64
    vx, vy, vz: f64
    mass:       f64
}

func offsetMomentum(bodies: [..] Body)
{
    var px, py, pz = 0.0'f64
    for b in bodies
    {
        px += b.vx * b.mass
        py += b.vy * b.mass
        pz += b.vz * b.mass
    }

    bodies[0].vx = -px / SOLAR_MASS
    bodies[0].vy = -py / SOLAR_MASS
    bodies[0].vz = -pz / SOLAR_MASS
}

func advance(bodies: [..] Body, dt: f64)
{
    for i in NB
    {
        let bi = &bodies[i]
        for j in i + 1 until NB
        {
            let bj  = &bodies[j]
            let dx  = bi.x - bj.x
            let dy  = bi.y - bj.y
            let dz  = bi.z - bj.z
            let d2  = dx * dx + dy * dy + dz * dz
            let mag = dt / (d2 * Swag.sqrt(d2))
            bi.vx -= dx * bj.mass * mag
            bi.vy -= dy * bj.mass * mag
            bi.vz -= dz * bj.mass * mag
            bj.vx += dx * bi.mass * mag
            bj.vy += dy * bi.mass * mag
            bj.vz += dz * bi.mass * mag
        }
    }

    for &b in bodies
    {
        b.x += dt * b.vx
        b.y += dt * b.vy
        b.z += dt * b.vz
    }
}

func energy(bodies: const [..] Body)->f64
{
    var e = 0.0'f64
    for i in NB
    {
        let bi = &bodies[i]
        e += 0.5'f64 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
        for j in i + 1 until NB
        {
            let bj = &bodies[j]
            let dx = bi.x - bj.x
            let dy = bi.y - bj.y
            let dz = bi.z - bj.z
            e -= (bi.mass * bj.mass) / Swag.sqrt(dx * dx + dy * dy + dz * dz)
        }
    }

    return e
}

#main
{
    // ---- data generation (not timed) ----
    var bodies: [NB] Body = [
        // sun
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS},
        // jupiter
        {4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01, 1.66007664274403694e-03 * DAYS_PER_YEAR, 7.69901118419740425e-03 * DAYS_PER_YEAR, -6.90460016972063023e-05 * DAYS_PER_YEAR, 9.54791938424326609e-04 * SOLAR_MASS},
        // saturn
        {8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01, -2.76742510726862411e-03 * DAYS_PER_YEAR, 4.99852801234917238e-03 * DAYS_PER_YEAR, 2.30417297573763929e-05 * DAYS_PER_YEAR, 2.85885980666130812e-04 * SOLAR_MASS},
        // uranus
        {1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01, 2.96460137564761618e-03 * DAYS_PER_YEAR, 2.37847173959480950e-03 * DAYS_PER_YEAR, -2.96589568540237556e-05 * DAYS_PER_YEAR, 4.36624404335156298e-05 * SOLAR_MASS},
        // neptune
        {1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01, 2.68067772490389322e-03 * DAYS_PER_YEAR, 1.62824170038242295e-03 * DAYS_PER_YEAR, -9.51592254519715870e-05 * DAYS_PER_YEAR, 5.15138902046611451e-05 * SOLAR_MASS}]

    // ---- timed work ----
    let t0 = now()

    offsetMomentum(bodies)
    for STEPS do
        advance(bodies, 0.01)
    let e = energy(bodies)

    let check = cast(u64) Swag.floor(-e * 1e12'f64)

    let t1 = now()
    report(check, t0, t1)
}

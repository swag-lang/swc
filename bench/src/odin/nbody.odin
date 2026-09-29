package main

import common "common"
import "core:math"

STEPS :: i64(500000)
NB :: i64(5)
PI :: f64(3.141592653589793)
SOLAR_MASS :: f64(4.0 * PI * PI)
DAYS_PER_YEAR :: f64(365.24)

Body :: struct {
    x, y, z, vx, vy, vz, mass: f64,
}

offset_momentum :: proc(bodies: ^[NB]Body) {
    px: f64 = 0.0
    py: f64 = 0.0
    pz: f64 = 0.0
    for i: i64 = 0; (i < NB); i += 1 {
        px += (bodies[i].vx * bodies[i].mass)
        py += (bodies[i].vy * bodies[i].mass)
        pz += (bodies[i].vz * bodies[i].mass)
    }
    bodies[0].vx = (-px / SOLAR_MASS)
    bodies[0].vy = (-py / SOLAR_MASS)
    bodies[0].vz = (-pz / SOLAR_MASS)
}

advance :: proc(bodies: ^[NB]Body, dt: f64) {
    for i: i64 = 0; (i < NB); i += 1 {
        bi := &bodies[i]
        for j: i64 = (i + 1); (j < NB); j += 1 {
            bj := &bodies[j]
            dx: f64 = (bi.x - bj.x)
            dy: f64 = (bi.y - bj.y)
            dz: f64 = (bi.z - bj.z)
            d2: f64 = (((dx * dx) + (dy * dy)) + (dz * dz))
            mag: f64 = (dt / (d2 * common.sqrt(d2)))
            bi.vx -= ((dx * bj.mass) * mag)
            bi.vy -= ((dy * bj.mass) * mag)
            bi.vz -= ((dz * bj.mass) * mag)
            bj.vx += ((dx * bi.mass) * mag)
            bj.vy += ((dy * bi.mass) * mag)
            bj.vz += ((dz * bi.mass) * mag)
        }
    }
    for i: i64 = 0; (i < NB); i += 1 {
        b := &bodies[i]
        b.x += (dt * b.vx)
        b.y += (dt * b.vy)
        b.z += (dt * b.vz)
    }
}

energy :: proc(bodies: ^[NB]Body) -> f64 {
    e: f64 = 0.0
    for i: i64 = 0; (i < NB); i += 1 {
        bi := &bodies[i]
        e += ((0.5 * bi.mass) * (((bi.vx * bi.vx) + (bi.vy * bi.vy)) + (bi.vz * bi.vz)))
        for j: i64 = (i + 1); (j < NB); j += 1 {
            bj := &bodies[j]
            dx: f64 = (bi.x - bj.x)
            dy: f64 = (bi.y - bj.y)
            dz: f64 = (bi.z - bj.z)
            e -= ((bi.mass * bj.mass) / common.sqrt((((dx * dx) + (dy * dy)) + (dz * dz))))
        }
    }
    return e
}

main :: proc() {
    bodies: [NB]Body = {
        // sun
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS},
        // jupiter
        {4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
         1.66007664274403694e-03 * DAYS_PER_YEAR, 7.69901118419740425e-03 * DAYS_PER_YEAR,
         -6.90460016972063023e-05 * DAYS_PER_YEAR, 9.54791938424326609e-04 * SOLAR_MASS},
        // saturn
        {8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
         -2.76742510726862411e-03 * DAYS_PER_YEAR, 4.99852801234917238e-03 * DAYS_PER_YEAR,
         2.30417297573763929e-05 * DAYS_PER_YEAR, 2.85885980666130812e-04 * SOLAR_MASS},
        // uranus
        {1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
         2.96460137564761618e-03 * DAYS_PER_YEAR, 2.37847173959480950e-03 * DAYS_PER_YEAR,
         -2.96589568540237556e-05 * DAYS_PER_YEAR, 4.36624404335156298e-05 * SOLAR_MASS},
        // neptune
        {1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
         2.68067772490389322e-03 * DAYS_PER_YEAR, 1.62824170038242295e-03 * DAYS_PER_YEAR,
         -9.51592254519715870e-05 * DAYS_PER_YEAR, 5.15138902046611451e-05 * SOLAR_MASS},
    }
    // Timed work starts after data generation.
    t0: f64 = common.now()
    offset_momentum(&bodies)
    for s: i64 = 0; (s < STEPS); s += 1 {
        advance(&bodies, 0.01)
    }
    e: f64 = energy(&bodies)
    check: u64 = u64(math.floor((-e * 1e12)))
    t1: f64 = common.now()
    common.report(check, t0, t1)
    return
}

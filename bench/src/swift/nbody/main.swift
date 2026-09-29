import WinSDK
import Foundation

let STEPS = 500000
let PI = 3.141592653589793
let SOLAR_MASS = 4.0 * PI * PI
let DAYS_PER_YEAR = 365.24

func now() -> Double {
    var c = LARGE_INTEGER()
    var f = LARGE_INTEGER()
    QueryPerformanceCounter(&c)
    QueryPerformanceFrequency(&f)
    return Double(c.QuadPart) / Double(f.QuadPart)
}

struct Body {
    var x, y, z, vx, vy, vz, mass: Double
}

func offsetMomentum(_ bodies: inout [Body]) {
    var px = 0.0, py = 0.0, pz = 0.0
    for b in bodies {
        px += b.vx * b.mass
        py += b.vy * b.mass
        pz += b.vz * b.mass
    }
    bodies[0].vx = -px / SOLAR_MASS
    bodies[0].vy = -py / SOLAR_MASS
    bodies[0].vz = -pz / SOLAR_MASS
}

func advance(_ bodies: inout [Body], _ dt: Double) {
    let nb = bodies.count
    for i in 0..<nb {
        for j in (i + 1)..<nb {
            let dx = bodies[i].x - bodies[j].x
            let dy = bodies[i].y - bodies[j].y
            let dz = bodies[i].z - bodies[j].z
            let d2 = dx * dx + dy * dy + dz * dz
            let mag = dt / (d2 * d2.squareRoot())
            let mi = bodies[i].mass
            let mj = bodies[j].mass
            bodies[i].vx -= dx * mj * mag
            bodies[i].vy -= dy * mj * mag
            bodies[i].vz -= dz * mj * mag
            bodies[j].vx += dx * mi * mag
            bodies[j].vy += dy * mi * mag
            bodies[j].vz += dz * mi * mag
        }
    }

    for i in 0..<nb {
        bodies[i].x += dt * bodies[i].vx
        bodies[i].y += dt * bodies[i].vy
        bodies[i].z += dt * bodies[i].vz
    }
}

func energy(_ bodies: [Body]) -> Double {
    var e = 0.0
    let nb = bodies.count
    for i in 0..<nb {
        let bi = bodies[i]
        e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
        for j in (i + 1)..<nb {
            let bj = bodies[j]
            let dx = bi.x - bj.x
            let dy = bi.y - bj.y
            let dz = bi.z - bj.z
            e -= (bi.mass * bj.mass) / (dx * dx + dy * dy + dz * dz).squareRoot()
        }
    }
    return e
}

func runMain() {
    // ---- data generation (not timed) ----
    var bodies: [Body] = [
        // sun
        Body(x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: SOLAR_MASS),
        // jupiter
        Body(x: 4.84143144246472090e+00, y: -1.16032004402742839e+00, z: -1.03622044471123109e-01,
             vx: 1.66007664274403694e-03 * DAYS_PER_YEAR, vy: 7.69901118419740425e-03 * DAYS_PER_YEAR,
             vz: -6.90460016972063023e-05 * DAYS_PER_YEAR, mass: 9.54791938424326609e-04 * SOLAR_MASS),
        // saturn
        Body(x: 8.34336671824457987e+00, y: 4.12479856412430479e+00, z: -4.03523417114321381e-01,
             vx: -2.76742510726862411e-03 * DAYS_PER_YEAR, vy: 4.99852801234917238e-03 * DAYS_PER_YEAR,
             vz: 2.30417297573763929e-05 * DAYS_PER_YEAR, mass: 2.85885980666130812e-04 * SOLAR_MASS),
        // uranus
        Body(x: 1.28943695621391310e+01, y: -1.51111514016986312e+01, z: -2.23307578892655734e-01,
             vx: 2.96460137564761618e-03 * DAYS_PER_YEAR, vy: 2.37847173959480950e-03 * DAYS_PER_YEAR,
             vz: -2.96589568540237556e-05 * DAYS_PER_YEAR, mass: 4.36624404335156298e-05 * SOLAR_MASS),
        // neptune
        Body(x: 1.53796971148509165e+01, y: -2.59193146099879641e+01, z: 1.79258772950371181e-01,
             vx: 2.68067772490389322e-03 * DAYS_PER_YEAR, vy: 1.62824170038242295e-03 * DAYS_PER_YEAR,
             vz: -9.51592254519715870e-05 * DAYS_PER_YEAR, mass: 5.15138902046611451e-05 * SOLAR_MASS),
    ]

    // ---- timed work ----
    let t0 = now()

    offsetMomentum(&bodies)
    for _ in 0..<STEPS {
        advance(&bodies, 0.01)
    }
    let e = energy(bodies)

    let check = UInt64((-e * 1e12).rounded(.down))

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()

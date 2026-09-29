// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const now = common.now;
const report = common.report;

const STEPS: i64 = 500000;
const NB: usize = 5;
const PI: f64 = 3.141592653589793;
const SOLAR_MASS: f64 = 4.0 * PI * PI;
const DAYS_PER_YEAR: f64 = 365.24;

const Body = struct {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
};

fn offsetMomentum(bodies: *[NB]Body) void {
    var px: f64 = 0.0;
    var py: f64 = 0.0;
    var pz: f64 = 0.0;
    for (bodies) |b| {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / SOLAR_MASS;
    bodies[0].vy = -py / SOLAR_MASS;
    bodies[0].vz = -pz / SOLAR_MASS;
}

fn advance(bodies: *[NB]Body, dt: f64) void {
    var i: usize = 0;
    while (i < NB) : (i += 1) {
        const bi = &bodies[i];
        var j: usize = i + 1;
        while (j < NB) : (j += 1) {
            const bj = &bodies[j];
            const dx = bi.x - bj.x;
            const dy = bi.y - bj.y;
            const dz = bi.z - bj.z;
            const d2 = dx * dx + dy * dy + dz * dz;
            const mag = dt / (d2 * @sqrt(d2));
            bi.vx -= dx * bj.mass * mag;
            bi.vy -= dy * bj.mass * mag;
            bi.vz -= dz * bj.mass * mag;
            bj.vx += dx * bi.mass * mag;
            bj.vy += dy * bi.mass * mag;
            bj.vz += dz * bi.mass * mag;
        }
    }

    for (bodies) |*b| {
        b.x += dt * b.vx;
        b.y += dt * b.vy;
        b.z += dt * b.vz;
    }
}

fn energy(bodies: *const [NB]Body) f64 {
    var e: f64 = 0.0;
    var i: usize = 0;
    while (i < NB) : (i += 1) {
        const bi = &bodies[i];
        e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz);
        var j: usize = i + 1;
        while (j < NB) : (j += 1) {
            const bj = &bodies[j];
            const dx = bi.x - bj.x;
            const dy = bi.y - bj.y;
            const dz = bi.z - bj.z;
            e -= (bi.mass * bj.mass) / @sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

pub fn main() void {
    var bodies = [NB]Body{
        // sun
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .vx = 0.0, .vy = 0.0, .vz = 0.0, .mass = SOLAR_MASS },
        // jupiter
        .{
            .x = 4.84143144246472090e+00,
            .y = -1.16032004402742839e+00,
            .z = -1.03622044471123109e-01,
            .vx = 1.66007664274403694e-03 * DAYS_PER_YEAR,
            .vy = 7.69901118419740425e-03 * DAYS_PER_YEAR,
            .vz = -6.90460016972063023e-05 * DAYS_PER_YEAR,
            .mass = 9.54791938424326609e-04 * SOLAR_MASS,
        },
        // saturn
        .{
            .x = 8.34336671824457987e+00,
            .y = 4.12479856412430479e+00,
            .z = -4.03523417114321381e-01,
            .vx = -2.76742510726862411e-03 * DAYS_PER_YEAR,
            .vy = 4.99852801234917238e-03 * DAYS_PER_YEAR,
            .vz = 2.30417297573763929e-05 * DAYS_PER_YEAR,
            .mass = 2.85885980666130812e-04 * SOLAR_MASS,
        },
        // uranus
        .{
            .x = 1.28943695621391310e+01,
            .y = -1.51111514016986312e+01,
            .z = -2.23307578892655734e-01,
            .vx = 2.96460137564761618e-03 * DAYS_PER_YEAR,
            .vy = 2.37847173959480950e-03 * DAYS_PER_YEAR,
            .vz = -2.96589568540237556e-05 * DAYS_PER_YEAR,
            .mass = 4.36624404335156298e-05 * SOLAR_MASS,
        },
        // neptune
        .{
            .x = 1.53796971148509165e+01,
            .y = -2.59193146099879641e+01,
            .z = 1.79258772950371181e-01,
            .vx = 2.68067772490389322e-03 * DAYS_PER_YEAR,
            .vy = 1.62824170038242295e-03 * DAYS_PER_YEAR,
            .vz = -9.51592254519715870e-05 * DAYS_PER_YEAR,
            .mass = 5.15138902046611451e-05 * SOLAR_MASS,
        },
    };

    // Timed work starts after data generation.
    const t0: f64 = now();

    offsetMomentum(&bodies);
    var s: i64 = 0;
    while (s < STEPS) : (s += 1) {
        advance(&bodies, 0.01);
    }
    const e = energy(&bodies);

    const check: u64 = @intFromFloat(@floor(-e * 1e12));

    const t1: f64 = now();
    report(check, t0, t1);
    return;
}

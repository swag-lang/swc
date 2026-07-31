use std::time::Instant;

const W: i64 = 480;
const H: i64 = 360;
const NS: usize = 4;

const SCX: [f64; 4] = [0.0, 2.0, -2.0, 0.0];
const SCY: [f64; 4] = [-0.5, 0.0, 0.0, -5001.0];
const SCZ: [f64; 4] = [3.0, 4.5, 4.0, 0.0];
const SRAD: [f64; 4] = [1.0, 1.0, 1.0, 5000.0];
const SR: [f64; 4] = [1.0, 0.2, 0.2, 0.9];
const SG: [f64; 4] = [0.25, 1.0, 0.3, 0.85];
const SB: [f64; 4] = [0.25, 0.3, 1.0, 0.3];
const SRE: [f64; 4] = [0.35, 0.45, 0.55, 0.15];

const LX: f64 = 5.0;
const LY: f64 = 5.0;
const LZ: f64 = -3.0;
const AMB: f64 = 0.12;

fn intersect(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, tmin: f64) -> (f64, i32) {
    let mut best = 1.0e30f64;
    let mut hit = -1i32;

    for i in 0..NS {
        let ex = ox - SCX[i];
        let ey = oy - SCY[i];
        let ez = oz - SCZ[i];
        let b = 2.0 * (ex * dx + ey * dy + ez * dz);
        let c = ex * ex + ey * ey + ez * ez - SRAD[i] * SRAD[i];
        let disc = b * b - 4.0 * c;
        if disc < 0.0 {
            continue;
        }

        let sq = disc.sqrt();
        let mut t = (-b - sq) * 0.5;
        if t < tmin {
            t = (-b + sq) * 0.5;
        }
        if t >= tmin && t < best {
            best = t;
            hit = i as i32;
        }
    }

    (best, hit)
}

fn trace(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, depth: i32) -> (f64, f64, f64) {
    let (t, hit) = intersect(ox, oy, oz, dx, dy, dz, 0.0001);
    if hit < 0 {
        return (0.05, 0.07, 0.12);
    }

    let hi = hit as usize;
    let px = ox + dx * t;
    let py = oy + dy * t;
    let pz = oz + dz * t;
    let nl = 1.0 / SRAD[hi];
    let nx = (px - SCX[hi]) * nl;
    let ny = (py - SCY[hi]) * nl;
    let nz = (pz - SCZ[hi]) * nl;

    let mut lx = LX - px;
    let mut ly = LY - py;
    let mut lz = LZ - pz;
    let ll = 1.0 / (lx * lx + ly * ly + lz * lz).sqrt();
    lx *= ll;
    ly *= ll;
    lz *= ll;

    let mut lam = nx * lx + ny * ly + nz * lz;
    if lam < 0.0 {
        lam = 0.0;
    } else {
        let (_, shadow) = intersect(px, py, pz, lx, ly, lz, 0.001);
        if shadow >= 0 {
            lam = 0.0;
        }
    }

    let k = AMB + 0.88 * lam;
    let mut cr = SR[hi] * k;
    let mut cg = SG[hi] * k;
    let mut cb = SB[hi] * k;

    let refl = SRE[hi];
    if refl > 0.0 && depth < 2 {
        let d = 2.0 * (dx * nx + dy * ny + dz * nz);
        let (rr, rg, rb) = trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1);
        cr = cr * (1.0 - refl) + rr * refl;
        cg = cg * (1.0 - refl) + rg * refl;
        cb = cb * (1.0 - refl) + rb * refl;
    }

    (cr, cg, cb)
}

fn main() {
    let start_t = Instant::now();

    let aspect = W as f64 / H as f64;
    let mut check: u64 = 0;

    for py in 0..H {
        for px in 0..W {
            let dx = ((px as f64 + 0.5) / W as f64 * 2.0 - 1.0) * aspect;
            let dy = 1.0 - (py as f64 + 0.5) / H as f64 * 2.0;
            let dz = 1.0f64;
            let il = 1.0 / (dx * dx + dy * dy + dz * dz).sqrt();
            let (r, g, b) = trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0);

            let mut ir = (r * 255.0) as i64;
            let mut ig = (g * 255.0) as i64;
            let mut ib = (b * 255.0) as i64;
            if ir > 255 {
                ir = 255;
            }
            if ig > 255 {
                ig = 255;
            }
            if ib > 255 {
                ib = 255;
            }
            check += (ir + 2 * ig + 3 * ib) as u64;
        }
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

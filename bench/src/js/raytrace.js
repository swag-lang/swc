const W = 480;
const H = 360;
const NS = 4;

const scx = [0.0, 2.0, -2.0, 0.0];
const scy = [-0.5, 0.0, 0.0, -5001.0];
const scz = [3.0, 4.5, 4.0, 0.0];
const srad = [1.0, 1.0, 1.0, 5000.0];
const sr = [1.0, 0.2, 0.2, 0.9];
const sg = [0.25, 1.0, 0.3, 0.85];
const sb = [0.25, 0.3, 1.0, 0.3];
const sre = [0.35, 0.45, 0.55, 0.15];

const LX = 5.0, LY = 5.0, LZ = -3.0;
const AMB = 0.12;

let hitT = 0.0;
let hitI = -1;

function intersect(ox, oy, oz, dx, dy, dz, tmin) {
    let best = 1e30;
    let hit = -1;
    for (let i = 0; i < NS; i++) {
        const ex = ox - scx[i];
        const ey = oy - scy[i];
        const ez = oz - scz[i];
        const b = 2.0 * (ex * dx + ey * dy + ez * dz);
        const c = ex * ex + ey * ey + ez * ez - srad[i] * srad[i];
        const disc = b * b - 4.0 * c;
        if (disc < 0.0) continue;
        const sq = Math.sqrt(disc);
        let t = (-b - sq) * 0.5;
        if (t < tmin) t = (-b + sq) * 0.5;
        if (t >= tmin && t < best) {
            best = t;
            hit = i;
        }
    }
    hitT = best;
    hitI = hit;
}

let outR = 0.0, outG = 0.0, outB = 0.0;

function trace(ox, oy, oz, dx, dy, dz, depth) {
    intersect(ox, oy, oz, dx, dy, dz, 0.0001);
    const t = hitT;
    const hit = hitI;
    if (hit < 0) {
        outR = 0.05; outG = 0.07; outB = 0.12;
        return;
    }

    const px = ox + dx * t;
    const py = oy + dy * t;
    const pz = oz + dz * t;
    const nl = 1.0 / srad[hit];
    const nx = (px - scx[hit]) * nl;
    const ny = (py - scy[hit]) * nl;
    const nz = (pz - scz[hit]) * nl;

    let lx = LX - px;
    let ly = LY - py;
    let lz = LZ - pz;
    const ll = 1.0 / Math.sqrt(lx * lx + ly * ly + lz * lz);
    lx *= ll; ly *= ll; lz *= ll;

    let lam = nx * lx + ny * ly + nz * lz;
    if (lam < 0.0) {
        lam = 0.0;
    } else {
        intersect(px, py, pz, lx, ly, lz, 0.001);
        if (hitI >= 0) lam = 0.0;
    }

    const k = AMB + 0.88 * lam;
    let cr = sr[hit] * k;
    let cg = sg[hit] * k;
    let cb = sb[hit] * k;

    const refl = sre[hit];
    if (refl > 0.0 && depth < 2) {
        const d = 2.0 * (dx * nx + dy * ny + dz * nz);
        trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1);
        cr = cr * (1.0 - refl) + outR * refl;
        cg = cg * (1.0 - refl) + outG * refl;
        cb = cb * (1.0 - refl) + outB * refl;
    }

    outR = cr; outG = cg; outB = cb;
}

// ---- timed work ----
const t0 = performance.now();

const aspect = W / H;
let check = 0;
for (let py = 0; py < H; py++) {
    for (let px = 0; px < W; px++) {
        const dx = ((px + 0.5) / W * 2.0 - 1.0) * aspect;
        const dy = 1.0 - (py + 0.5) / H * 2.0;
        const dz = 1.0;
        const il = 1.0 / Math.sqrt(dx * dx + dy * dy + dz * dz);
        trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0);
        let ir = Math.floor(outR * 255.0);
        let ig = Math.floor(outG * 255.0);
        let ib = Math.floor(outB * 255.0);
        if (ir > 255) ir = 255;
        if (ig > 255) ig = 255;
        if (ib > 255) ib = 255;
        check += ir + 2 * ig + 3 * ib;
    }
}

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));

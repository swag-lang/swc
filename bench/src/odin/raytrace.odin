package main

import common "common"

W :: i64(480)
H :: i64(360)
NS :: u64(4)
SCX: [4]f64 = [4]f64{0.0, 2.0, -2.0, 0.0}
SCY: [4]f64 = [4]f64{-0.5, 0.0, 0.0, -5001.0}
SCZ: [4]f64 = [4]f64{3.0, 4.5, 4.0, 0.0}
SRAD: [4]f64 = [4]f64{1.0, 1.0, 1.0, 5000.0}
SR: [4]f64 = [4]f64{1.0, 0.2, 0.2, 0.9}
SG: [4]f64 = [4]f64{0.25, 1.0, 0.3, 0.85}
SB: [4]f64 = [4]f64{0.25, 0.3, 1.0, 0.3}
SRE: [4]f64 = [4]f64{0.35, 0.45, 0.55, 0.15}
LX :: f64(5.0)
LY :: f64(5.0)
LZ :: f64(-3.0)
AMB :: f64(0.12)
g_HitT: f64 = 0.0
g_HitI: i32 = -1
g_OutR: f64 = 0.0
g_OutG: f64 = 0.0
g_OutB: f64 = 0.0
intersect :: proc(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, tmin: f64) {
    best: f64 = 1.0e30
    hit: i32 = -1
    for i: u64 = 0; (i < NS); i += 1 {
        ex: f64 = (ox - SCX[i])
        ey: f64 = (oy - SCY[i])
        ez: f64 = (oz - SCZ[i])
        b: f64 = (2.0 * (((ex * dx) + (ey * dy)) + (ez * dz)))
        c: f64 = ((((ex * ex) + (ey * ey)) + (ez * ez)) - (SRAD[i] * SRAD[i]))
        disc: f64 = ((b * b) - (4.0 * c))
        if (disc < 0.0) {
            continue
        }
        sq: f64 = common.sqrt(disc)
        t: f64 = ((-b - sq) * 0.5)
        if (t < tmin) {
            t = ((-b + sq) * 0.5)
        }
        if ((t >= tmin) && (t < best)) {
            best = t
            hit = i32(i)
        }
    }
    g_HitT = best
    g_HitI = hit
}

trace :: proc(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, depth: i32) {
    intersect(ox, oy, oz, dx, dy, dz, 0.0001)
    t: f64 = g_HitT
    hit: i32 = g_HitI
    if (hit < 0) {
        g_OutR = 0.05
        g_OutG = 0.07
        g_OutB = 0.12
        return
    }
    hi: u64 = u64(hit)
    px: f64 = (ox + (dx * t))
    py: f64 = (oy + (dy * t))
    pz: f64 = (oz + (dz * t))
    nl: f64 = (1.0 / SRAD[hi])
    nx: f64 = ((px - SCX[hi]) * nl)
    ny: f64 = ((py - SCY[hi]) * nl)
    nz: f64 = ((pz - SCZ[hi]) * nl)
    lx: f64 = (LX - px)
    ly: f64 = (LY - py)
    lz: f64 = (LZ - pz)
    ll: f64 = (1.0 / common.sqrt((((lx * lx) + (ly * ly)) + (lz * lz))))
    lx *= ll
    ly *= ll
    lz *= ll
    lam: f64 = (((nx * lx) + (ny * ly)) + (nz * lz))
    if (lam < 0.0) {
        lam = 0.0
    } else {
        intersect(px, py, pz, lx, ly, lz, 0.001)
        if (g_HitI >= 0) {
            lam = 0.0
        }
    }
    k: f64 = (AMB + (0.88 * lam))
    cr: f64 = (SR[hi] * k)
    cg: f64 = (SG[hi] * k)
    cb: f64 = (SB[hi] * k)
    refl: f64 = SRE[hi]
    if ((refl > 0.0) && (depth < 2)) {
        d: f64 = (2.0 * (((dx * nx) + (dy * ny)) + (dz * nz)))
        trace(px, py, pz, (dx - (d * nx)), (dy - (d * ny)), (dz - (d * nz)), (depth + 1))
        cr = ((cr * (1.0 - refl)) + (g_OutR * refl))
        cg = ((cg * (1.0 - refl)) + (g_OutG * refl))
        cb = ((cb * (1.0 - refl)) + (g_OutB * refl))
    }
    g_OutR = cr
    g_OutG = cg
    g_OutB = cb
}

main :: proc() {
    t0: f64 = common.now()
    aspect: f64 = (f64(W) / f64(H))
    check: u64 = 0
    for py: i64 = 0; (py < H); py += 1 {
        for px: i64 = 0; (px < W); px += 1 {
            dx: f64 = (((((f64(px) + 0.5) / f64(W)) * 2.0) - 1.0) * aspect)
            dy: f64 = (1.0 - (((f64(py) + 0.5) / f64(H)) * 2.0))
            dz: f64 = 1.0
            il: f64 = (1.0 / common.sqrt((((dx * dx) + (dy * dy)) + (dz * dz))))
            trace(0.0, 0.0, 0.0, (dx * il), (dy * il), (dz * il), 0)
            ir: i64 = i64((g_OutR * 255.0))
            ig: i64 = i64((g_OutG * 255.0))
            ib: i64 = i64((g_OutB * 255.0))
            if (ir > 255) {
                ir = 255
            }
            if (ig > 255) {
                ig = 255
            }
            if (ib > 255) {
                ib = 255
            }
            check += u64(((ir + (2 * ig)) + (3 * ib)))
        }
    }
    t1: f64 = common.now()
    common.report(check, t0, t1)
    return
}


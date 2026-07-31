const W  = 480
const H  = 360
const NS = 4

const SCX:  [4] f64 = [0.0, 2.0, -2.0, 0.0]
const SCY:  [4] f64 = [-0.5, 0.0, 0.0, -5001.0]
const SCZ:  [4] f64 = [3.0, 4.5, 4.0, 0.0]
const SRAD: [4] f64 = [1.0, 1.0, 1.0, 5000.0]
const SR:   [4] f64 = [1.0, 0.2, 0.2, 0.9]
const SG:   [4] f64 = [0.25, 1.0, 0.3, 0.85]
const SB:   [4] f64 = [0.25, 0.3, 1.0, 0.3]
const SRE:  [4] f64 = [0.35, 0.45, 0.55, 0.15]

const LX  = 5.0'f64
const LY  = 5.0'f64
const LZ  = -3.0'f64
const AMB = 0.12'f64

var g_HitT = 0.0'f64
var g_HitI = -1's32

var g_OutR = 0.0'f64
var g_OutG = 0.0'f64
var g_OutB = 0.0'f64

func intersect(ox, oy, oz, dx, dy, dz, tmin: f64)
{
    var best = 1.0e30'f64
    var hit  = -1's32

    for [i] in NS
    {
        let ex   = ox - SCX[i]
        let ey   = oy - SCY[i]
        let ez   = oz - SCZ[i]
        let b    = 2.0'f64 * (ex * dx + ey * dy + ez * dz)
        let c    = ex * ex + ey * ey + ez * ez - SRAD[i] * SRAD[i]
        let disc = b * b - 4.0'f64 * c
        if disc < 0.0'f64 do
            continue

        let sq = @sqrt(disc)
        var t  = (-b - sq) * 0.5'f64
        if t < tmin do
            t = (-b + sq) * 0.5'f64
        if t >= tmin and t < best
        {
            best = t
            hit  = cast(s32) i
        }
    }

    g_HitT = best
    g_HitI = hit
}

func trace(ox, oy, oz, dx, dy, dz: f64, depth: s32)
{
    intersect(ox, oy, oz, dx, dy, dz, 0.0001'f64)
    let t   = g_HitT
    let hit = g_HitI
    if hit < 0
    {
        g_OutR = 0.05'f64
        g_OutG = 0.07'f64
        g_OutB = 0.12'f64
        return
    }

    let hi = cast(u64) hit
    let px = ox + dx * t
    let py = oy + dy * t
    let pz = oz + dz * t
    let nl = 1.0'f64 / SRAD[hi]
    let nx = (px - SCX[hi]) * nl
    let ny = (py - SCY[hi]) * nl
    let nz = (pz - SCZ[hi]) * nl

    var lx = LX - px
    var ly = LY - py
    var lz = LZ - pz
    let ll = 1.0'f64 / @sqrt(lx * lx + ly * ly + lz * lz)
    lx *= ll
    ly *= ll
    lz *= ll

    var lam = nx * lx + ny * ly + nz * lz
    if lam < 0.0'f64
    {
        lam = 0.0'f64
    }
    else
    {
        intersect(px, py, pz, lx, ly, lz, 0.001'f64)
        if g_HitI >= 0 do
            lam = 0.0'f64
    }

    let k  = AMB + 0.88'f64 * lam
    var cr = SR[hi] * k
    var cg = SG[hi] * k
    var cb = SB[hi] * k

    let refl = SRE[hi]
    if refl > 0.0'f64 and depth < 2
    {
        let d = 2.0'f64 * (dx * nx + dy * ny + dz * nz)
        trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1)
        cr = cr * (1.0'f64 - refl) + g_OutR * refl
        cg = cg * (1.0'f64 - refl) + g_OutG * refl
        cb = cb * (1.0'f64 - refl) + g_OutB * refl
    }

    g_OutR = cr
    g_OutG = cg
    g_OutB = cb
}

#main
{
    let t0 = now()

    let aspect = cast(f64) W / cast(f64) H
    var check  = 0'u64

    for [py] in H
    {
        for [px] in W
        {
            let dx = ((cast(f64) px + 0.5'f64) / cast(f64) W * 2.0'f64 - 1.0'f64) * aspect
            let dy = 1.0'f64 - (cast(f64) py + 0.5'f64) / cast(f64) H * 2.0'f64
            let dz = 1.0'f64
            let il = 1.0'f64 / @sqrt(dx * dx + dy * dy + dz * dz)
            trace(0.0'f64, 0.0'f64, 0.0'f64, dx * il, dy * il, dz * il, 0)

            var ir = cast(s64)(g_OutR * 255.0'f64)
            var ig = cast(s64)(g_OutG * 255.0'f64)
            var ib = cast(s64)(g_OutB * 255.0'f64)
            if ir > 255 do
                ir = 255
            if ig > 255 do
                ig = 255
            if ib > 255 do
                ib = 255
            check += cast(u64)(ir + 2 * ig + 3 * ib)
        }
    }

    let t1 = now()
    report(check, t0, t1)
}

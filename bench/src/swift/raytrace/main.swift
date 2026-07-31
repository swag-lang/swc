import WinSDK
import Foundation

let W = 480
let H = 360
let NS = 4

let SCX: [Double] = [0.0, 2.0, -2.0, 0.0]
let SCY: [Double] = [-0.5, 0.0, 0.0, -5001.0]
let SCZ: [Double] = [3.0, 4.5, 4.0, 0.0]
let SRAD: [Double] = [1.0, 1.0, 1.0, 5000.0]
let SR: [Double] = [1.0, 0.2, 0.2, 0.9]
let SG: [Double] = [0.25, 1.0, 0.3, 0.85]
let SB: [Double] = [0.25, 0.3, 1.0, 0.3]
let SRE: [Double] = [0.35, 0.45, 0.55, 0.15]

let LX = 5.0
let LY = 5.0
let LZ = -3.0
let AMB = 0.12

func now() -> Double {
    var c = LARGE_INTEGER()
    var f = LARGE_INTEGER()
    QueryPerformanceCounter(&c)
    QueryPerformanceFrequency(&f)
    return Double(c.QuadPart) / Double(f.QuadPart)
}

var gHitT = 0.0
var gHitI = -1

var gOutR = 0.0
var gOutG = 0.0
var gOutB = 0.0

func intersect(_ ox: Double, _ oy: Double, _ oz: Double,
               _ dx: Double, _ dy: Double, _ dz: Double, _ tmin: Double) {
    var best = 1.0e30
    var hit = -1

    for i in 0..<NS {
        let ex = ox - SCX[i]
        let ey = oy - SCY[i]
        let ez = oz - SCZ[i]
        let b = 2.0 * (ex * dx + ey * dy + ez * dz)
        let c = ex * ex + ey * ey + ez * ez - SRAD[i] * SRAD[i]
        let disc = b * b - 4.0 * c
        if disc < 0.0 {
            continue
        }

        let sq = disc.squareRoot()
        var t = (-b - sq) * 0.5
        if t < tmin {
            t = (-b + sq) * 0.5
        }
        if t >= tmin && t < best {
            best = t
            hit = i
        }
    }

    gHitT = best
    gHitI = hit
}

func trace(_ ox: Double, _ oy: Double, _ oz: Double,
           _ dx: Double, _ dy: Double, _ dz: Double, _ depth: Int) {
    intersect(ox, oy, oz, dx, dy, dz, 0.0001)
    let t = gHitT
    let hit = gHitI
    if hit < 0 {
        gOutR = 0.05
        gOutG = 0.07
        gOutB = 0.12
        return
    }

    let hi = hit
    let px = ox + dx * t
    let py = oy + dy * t
    let pz = oz + dz * t
    let nl = 1.0 / SRAD[hi]
    let nx = (px - SCX[hi]) * nl
    let ny = (py - SCY[hi]) * nl
    let nz = (pz - SCZ[hi]) * nl

    var lx = LX - px
    var ly = LY - py
    var lz = LZ - pz
    let ll = 1.0 / (lx * lx + ly * ly + lz * lz).squareRoot()
    lx *= ll
    ly *= ll
    lz *= ll

    var lam = nx * lx + ny * ly + nz * lz
    if lam < 0.0 {
        lam = 0.0
    } else {
        intersect(px, py, pz, lx, ly, lz, 0.001)
        if gHitI >= 0 {
            lam = 0.0
        }
    }

    let k = AMB + 0.88 * lam
    var cr = SR[hi] * k
    var cg = SG[hi] * k
    var cb = SB[hi] * k

    let refl = SRE[hi]
    if refl > 0.0 && depth < 2 {
        let d = 2.0 * (dx * nx + dy * ny + dz * nz)
        trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1)
        cr = cr * (1.0 - refl) + gOutR * refl
        cg = cg * (1.0 - refl) + gOutG * refl
        cb = cb * (1.0 - refl) + gOutB * refl
    }

    gOutR = cr
    gOutG = cg
    gOutB = cb
}

// The whole `#main` body lives in a function so that locals stay locals:
// top-level variables in main.swift are globals and defeat several optimisations.
func runMain() {
let t0 = now()

let aspect = Double(W) / Double(H)
var check: UInt64 = 0

for py in 0..<H {
    for px in 0..<W {
        let dx = ((Double(px) + 0.5) / Double(W) * 2.0 - 1.0) * aspect
        let dy = 1.0 - (Double(py) + 0.5) / Double(H) * 2.0
        let dz = 1.0
        let il = 1.0 / (dx * dx + dy * dy + dz * dz).squareRoot()
        trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0)

        var ir = Int(gOutR * 255.0)
        var ig = Int(gOutG * 255.0)
        var ib = Int(gOutB * 255.0)
        if ir > 255 {
            ir = 255
        }
        if ig > 255 {
            ig = 255
        }
        if ib > 255 {
            ib = 255
        }
        check &+= UInt64(ir + 2 * ig + 3 * ib)
    }
}

let t1 = now()
print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()

// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const now = common.now;
const report = common.report;

const W: i64 = 480;
const H: i64 = 360;
const NS: u64 = 4;
const SCX: [4]f64 = [4]f64{0.0, 2.0, -2.0, 0.0};
const SCY: [4]f64 = [4]f64{-0.5, 0.0, 0.0, -5001.0};
const SCZ: [4]f64 = [4]f64{3.0, 4.5, 4.0, 0.0};
const SRAD: [4]f64 = [4]f64{1.0, 1.0, 1.0, 5000.0};
const SR: [4]f64 = [4]f64{1.0, 0.2, 0.2, 0.9};
const SG: [4]f64 = [4]f64{0.25, 1.0, 0.3, 0.85};
const SB: [4]f64 = [4]f64{0.25, 0.3, 1.0, 0.3};
const SRE: [4]f64 = [4]f64{0.35, 0.45, 0.55, 0.15};
const LX: f64 = 5.0;
const LY: f64 = 5.0;
const LZ: f64 = -3.0;
const AMB: f64 = 0.12;
var g_HitT: f64 = 0.0;
var g_HitI: i32 = -1;
var g_OutR: f64 = 0.0;
var g_OutG: f64 = 0.0;
var g_OutB: f64 = 0.0;
fn intersect(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, tmin: f64) void {
    var best: f64 = 1.0e30;
    var hit: i32 = -1;
    {
        var i: u64 = 0;
        while ((i < NS)) : (i += 1) {
            const ex: f64 = (ox - SCX[i]);
            const ey: f64 = (oy - SCY[i]);
            const ez: f64 = (oz - SCZ[i]);
            const b: f64 = (2.0 * (((ex * dx) + (ey * dy)) + (ez * dz)));
            const c: f64 = ((((ex * ex) + (ey * ey)) + (ez * ez)) - (SRAD[i] * SRAD[i]));
            const disc: f64 = ((b * b) - (4.0 * c));
            if ((disc < 0.0)) {
                continue;
            }
            const sq: f64 = @sqrt(disc);
            var t: f64 = ((-b - sq) * 0.5);
            if ((t < tmin)) {
                t = ((-b + sq) * 0.5);
            }
            if (((t >= tmin) and (t < best))) {
                best = t;
                hit = @as(i32, @intCast(i));
            }
        }
    }
    g_HitT = best;
    g_HitI = hit;
}

fn trace(ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, depth: i32) void {
    intersect(ox, oy, oz, dx, dy, dz, 0.0001);
    const t: f64 = g_HitT;
    const hit: i32 = g_HitI;
    if ((hit < 0)) {
        g_OutR = 0.05;
        g_OutG = 0.07;
        g_OutB = 0.12;
        return;
    }
    const hi: u64 = @as(u64, @intCast(hit));
    const px: f64 = (ox + (dx * t));
    const py: f64 = (oy + (dy * t));
    const pz: f64 = (oz + (dz * t));
    const nl: f64 = (1.0 / SRAD[hi]);
    const nx: f64 = ((px - SCX[hi]) * nl);
    const ny: f64 = ((py - SCY[hi]) * nl);
    const nz: f64 = ((pz - SCZ[hi]) * nl);
    var lx: f64 = (LX - px);
    var ly: f64 = (LY - py);
    var lz: f64 = (LZ - pz);
    const ll: f64 = (1.0 / @sqrt((((lx * lx) + (ly * ly)) + (lz * lz))));
    lx *= ll;
    ly *= ll;
    lz *= ll;
    var lam: f64 = (((nx * lx) + (ny * ly)) + (nz * lz));
    if ((lam < 0.0)) {
        lam = 0.0;
    } else {
        intersect(px, py, pz, lx, ly, lz, 0.001);
        if ((g_HitI >= 0)) {
            lam = 0.0;
        }
    }
    const k: f64 = (AMB + (0.88 * lam));
    var cr: f64 = (SR[hi] * k);
    var cg: f64 = (SG[hi] * k);
    var cb: f64 = (SB[hi] * k);
    const refl: f64 = SRE[hi];
    if (((refl > 0.0) and (depth < 2))) {
        const d: f64 = (2.0 * (((dx * nx) + (dy * ny)) + (dz * nz)));
        trace(px, py, pz, (dx - (d * nx)), (dy - (d * ny)), (dz - (d * nz)), (depth + 1));
        cr = ((cr * (1.0 - refl)) + (g_OutR * refl));
        cg = ((cg * (1.0 - refl)) + (g_OutG * refl));
        cb = ((cb * (1.0 - refl)) + (g_OutB * refl));
    }
    g_OutR = cr;
    g_OutG = cg;
    g_OutB = cb;
}

pub fn main() void {
    const t0: f64 = now();
    const aspect: f64 = (@as(f64, @floatFromInt(W)) / @as(f64, @floatFromInt(H)));
    var check: u64 = 0;
    {
        var py: i64 = 0;
        while ((py < H)) : (py += 1) {
            {
                var px: i64 = 0;
                while ((px < W)) : (px += 1) {
                    const dx: f64 = (((((@as(f64, @floatFromInt(px)) + 0.5) / @as(f64, @floatFromInt(W))) * 2.0) - 1.0) * aspect);
                    const dy: f64 = (1.0 - (((@as(f64, @floatFromInt(py)) + 0.5) / @as(f64, @floatFromInt(H))) * 2.0));
                    const dz: f64 = 1.0;
                    const il: f64 = (1.0 / @sqrt((((dx * dx) + (dy * dy)) + (dz * dz))));
                    trace(0.0, 0.0, 0.0, (dx * il), (dy * il), (dz * il), 0);
                    var ir: i64 = @as(i64, @intFromFloat((g_OutR * 255.0)));
                    var ig: i64 = @as(i64, @intFromFloat((g_OutG * 255.0)));
                    var ib: i64 = @as(i64, @intFromFloat((g_OutB * 255.0)));
                    if ((ir > 255)) {
                        ir = 255;
                    }
                    if ((ig > 255)) {
                        ig = 255;
                    }
                    if ((ib > 255)) {
                        ib = 255;
                    }
                    check += @as(u64, @intCast(((ir + (2 * ig)) + (3 * ib))));
                }
            }
        }
    }
    const t1: f64 = now();
    report(check, t0, t1);
    return;
}


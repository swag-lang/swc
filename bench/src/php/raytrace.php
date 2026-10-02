<?php
const W = 480;
const H = 360;
const NS = 4;
$scx = [0.0, 2.0, (-2.0), 0.0];
$scy = [(-0.5), 0.0, 0.0, (-5001.0)];
$scz = [3.0, 4.5, 4.0, 0.0];
$srad = [1.0, 1.0, 1.0, 5000.0];
$sr = [1.0, 0.2, 0.2, 0.9];
$sg = [0.25, 1.0, 0.3, 0.85];
$sb = [0.25, 0.3, 1.0, 0.3];
$sre = [0.35, 0.45, 0.55, 0.15];
const LX = 5.0;
const LY = 5.0;
const LZ = (-3.0);
const AMB = 0.12;

function intersect($ox, $oy, $oz, $dx, $dy, $dz, $tmin) {
    global $scx, $scy, $scz, $srad;
    $best = 1e30;
    $hit = (-1);
    for ($i = 0; $i < NS; $i += 1) {
        $ex = ($ox - $scx[$i]);
        $ey = ($oy - $scy[$i]);
        $ez = ($oz - $scz[$i]);
        $b = (2.0 * ((($ex * $dx) + ($ey * $dy)) + ($ez * $dz)));
        $c = (((($ex * $ex) + ($ey * $ey)) + ($ez * $ez)) - ($srad[$i] * $srad[$i]));
        $disc = (($b * $b) - (4.0 * $c));
        if (($disc < 0.0)) {
            continue;
        }
        $sq = sqrt($disc);
        $t = (((-$b) - $sq) * 0.5);
        if (($t < $tmin)) {
            $t = (((-$b) + $sq) * 0.5);
        }
        if ((($t >= $tmin) && ($t < $best))) {
            $best = $t;
            $hit = $i;
        }
    }
    return [$best, $hit];
}

function trace($ox, $oy, $oz, $dx, $dy, $dz, $depth) {
    global $sb, $scx, $scy, $scz, $sg, $sr, $srad, $sre;
    [$t, $hit] = intersect($ox, $oy, $oz, $dx, $dy, $dz, 0.0001);
    if (($hit < 0)) {
        return [0.05, 0.07, 0.12];
    }
    $px = ($ox + ($dx * $t));
    $py = ($oy + ($dy * $t));
    $pz = ($oz + ($dz * $t));
    $nx = ($px - $scx[$hit]);
    $ny = ($py - $scy[$hit]);
    $nz = ($pz - $scz[$hit]);
    $nl = (1.0 / $srad[$hit]);
    $nx *= $nl;
    $ny *= $nl;
    $nz *= $nl;
    $lx = (LX - $px);
    $ly = (LY - $py);
    $lz = (LZ - $pz);
    $ll = (1.0 / sqrt(((($lx * $lx) + ($ly * $ly)) + ($lz * $lz))));
    $lx *= $ll;
    $ly *= $ll;
    $lz *= $ll;
    $lam = ((($nx * $lx) + ($ny * $ly)) + ($nz * $lz));
    if (($lam < 0.0)) {
        $lam = 0.0;
    } else {
        [$st, $sh] = intersect($px, $py, $pz, $lx, $ly, $lz, 0.001);
        if (($sh >= 0)) {
            $lam = 0.0;
        }
    }
    $k = (AMB + (0.88 * $lam));
    $cr = ($sr[$hit] * $k);
    $cg = ($sg[$hit] * $k);
    $cb = ($sb[$hit] * $k);
    $refl = $sre[$hit];
    if ((($refl > 0.0) && ($depth < 2))) {
        $d = (2.0 * ((($dx * $nx) + ($dy * $ny)) + ($dz * $nz)));
        $rx = ($dx - ($d * $nx));
        $ry = ($dy - ($d * $ny));
        $rz = ($dz - ($d * $nz));
        [$rr, $rg, $rb] = trace($px, $py, $pz, $rx, $ry, $rz, ($depth + 1));
        $cr = (($cr * (1.0 - $refl)) + ($rr * $refl));
        $cg = (($cg * (1.0 - $refl)) + ($rg * $refl));
        $cb = (($cb * (1.0 - $refl)) + ($rb * $refl));
    }
    return [$cr, $cg, $cb];
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$aspect = ((float) (W) / (float) (H));
$check = 0;
for ($py = 0; $py < H; $py += 1) {
    for ($px = 0; $px < W; $px += 1) {
        $dx = ((((($px + 0.5) / W) * 2.0) - 1.0) * $aspect);
        $dy = (1.0 - ((($py + 0.5) / H) * 2.0));
        $dz = 1.0;
        $il = (1.0 / sqrt(((($dx * $dx) + ($dy * $dy)) + ($dz * $dz))));
        [$cr, $cg, $cb] = trace(0.0, 0.0, 0.0, ($dx * $il), ($dy * $il), ($dz * $il), 0);
        $ir = (int) (($cr * 255.0));
        $ig = (int) (($cg * 255.0));
        $ib = (int) (($cb * 255.0));
        if (($ir > 255)) {
            $ir = 255;
        }
        if (($ig > 255)) {
            $ig = 255;
        }
        if (($ib > 255)) {
            $ib = 255;
        }
        $check += (($ir + (2 * $ig)) + (3 * $ib));
    }
}
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

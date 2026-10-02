<?php
const N = 9;
$perm = array_fill(0, N, 0);
$perm1 = array_fill(0, N, 0);
$count = array_fill(0, N, 0);

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
for ($i = 0; $i < N; $i += 1) {
    $perm1[$i] = $i;
}
$checksum = 0;
$max_flips = 0;
$perm_count = 0;
$r = N;
while (true) {
    while (($r != 1)) {
        $count[($r - 1)] = $r;
        $r -= 1;
    }
    for ($i = 0; $i < N; $i += 1) {
        $perm[$i] = $perm1[$i];
    }
    $flips = 0;
    $k = $perm[0];
    while (($k != 0)) {
        $i = 0;
        $j = $k;
        while (($i < $j)) {
            [$perm[$i], $perm[$j]] = [$perm[$j], $perm[$i]];
            $i += 1;
            $j -= 1;
        }
        $flips += 1;
        $k = $perm[0];
    }
    if (($flips > $max_flips)) {
        $max_flips = $flips;
    }
    if ((($perm_count % 2) == 0)) {
        $checksum += $flips;
    } else {
        $checksum -= $flips;
    }
    $done = false;
    while (true) {
        if (($r == N)) {
            $done = true;
            break;
        }
        $perm0 = $perm1[0];
        for ($i = 0; $i < $r; $i += 1) {
            $perm1[$i] = $perm1[($i + 1)];
        }
        $perm1[$r] = $perm0;
        $count[$r] -= 1;
        if (($count[$r] > 0)) {
            break;
        }
        $r += 1;
    }
    if ($done) {
        break;
    }
    $perm_count += 1;
}
$check = (($checksum * 1000) + $max_flips);
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

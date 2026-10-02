<?php
const N = 300000;
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

function qsort(&$a, $lo, $hi) {
    while ((($hi - $lo) > 16)) {
        $mid = ($lo + intdiv(($hi - $lo), 2));
        if (($a[$mid] < $a[$lo])) {
            [$a[$lo], $a[$mid]] = [$a[$mid], $a[$lo]];
        }
        if (($a[$hi] < $a[$lo])) {
            [$a[$lo], $a[$hi]] = [$a[$hi], $a[$lo]];
        }
        if (($a[$hi] < $a[$mid])) {
            [$a[$mid], $a[$hi]] = [$a[$hi], $a[$mid]];
        }
        $pivot = $a[$mid];
        $i = $lo;
        $j = $hi;
        while (true) {
            while (($a[$i] < $pivot)) {
                $i += 1;
            }
            while (($a[$j] > $pivot)) {
                $j -= 1;
            }
            if (($i <= $j)) {
                [$a[$i], $a[$j]] = [$a[$j], $a[$i]];
                $i += 1;
                $j -= 1;
            }
            if (($i > $j)) {
                break;
            }
        }
        if ((($j - $lo) < ($hi - $i))) {
            qsort($a, $lo, $j);
            $lo = $i;
        } else {
            qsort($a, $i, $hi);
            $hi = $j;
        }
    }
    for ($i = ($lo + 1); $i < ($hi + 1); $i += 1) {
        $v = $a[$i];
        $j = ($i - 1);
        while ((($j >= $lo) && ($a[$j] > $v))) {
            $a[($j + 1)] = $a[$j];
            $j -= 1;
        }
        $a[($j + 1)] = $v;
    }
}

$a = array_fill(0, N, 0);
for ($i = 0; $i < N; $i += 1) {
    $a[$i] = rnd();
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
qsort($a, 0, (N - 1));
$is_sorted = true;
for ($i = 1; $i < N; $i += 1) {
    if (($a[($i - 1)] > $a[$i])) {
        $is_sorted = false;
    }
}
$check = 0;
if ($is_sorted) {
    for ($i = 0; $i < N; $i += 1) {
        $check += (($a[$i] % 1000) * (($i % 7) + 1));
    }
}
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

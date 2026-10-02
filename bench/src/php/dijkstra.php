<?php
const N = 800;
const NN = (N * N);
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

$weight = array_fill(0, NN, 0);
for ($i = 0; $i < NN; $i += 1) {
    $weight[$i] = (1 + (rnd() % 9));
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
const INF = (1 << 60);
$dist = array_fill(0, NN, INF);
$hd = array_fill(0, (NN * 4), 0);
$hn = array_fill(0, (NN * 4), 0);
$hsize = 0;

function push($d, $node) {
    global $hd, $hn, $hsize;
    $i = $hsize;
    $hsize += 1;
    $hd[$i] = $d;
    $hn[$i] = $node;
    while (($i > 0)) {
        $p = (($i - 1) >> 1);
        if (($hd[$p] <= $hd[$i])) {
            break;
        }
        [$hd[$p], $hd[$i]] = [$hd[$i], $hd[$p]];
        [$hn[$p], $hn[$i]] = [$hn[$i], $hn[$p]];
        $i = $p;
    }
}

function pop() {
    global $hd, $hn, $hsize;
    $rd = $hd[0];
    $rn = $hn[0];
    $hsize -= 1;
    $hd[0] = $hd[$hsize];
    $hn[0] = $hn[$hsize];
    $i = 0;
    while (true) {
        $l = ((2 * $i) + 1);
        if (($l >= $hsize)) {
            break;
        }
        $r = ($l + 1);
        $m = $l;
        if ((($r < $hsize) && ($hd[$r] < $hd[$l]))) {
            $m = $r;
        }
        if (($hd[$i] <= $hd[$m])) {
            break;
        }
        [$hd[$m], $hd[$i]] = [$hd[$i], $hd[$m]];
        [$hn[$m], $hn[$i]] = [$hn[$i], $hn[$m]];
        $i = $m;
    }
    return [$rd, $rn];
}

$dist[0] = 0;
push(0, 0);
$pops = 0;
$target = (NN - 1);
while (($hsize > 0)) {
    [$d, $u] = pop();
    $pops += 1;
    if (($d > $dist[$u])) {
        continue;
    }
    if (($u == $target)) {
        break;
    }
    $x = ($u % N);
    $y = intdiv($u, N);
    if (($x > 0)) {
        $v = ($u - 1);
        $nd = ($d + $weight[$v]);
        if (($nd < $dist[$v])) {
            $dist[$v] = $nd;
            push($nd, $v);
        }
    }
    if (($x < (N - 1))) {
        $v = ($u + 1);
        $nd = ($d + $weight[$v]);
        if (($nd < $dist[$v])) {
            $dist[$v] = $nd;
            push($nd, $v);
        }
    }
    if (($y > 0)) {
        $v = ($u - N);
        $nd = ($d + $weight[$v]);
        if (($nd < $dist[$v])) {
            $dist[$v] = $nd;
            push($nd, $v);
        }
    }
    if (($y < (N - 1))) {
        $v = ($u + N);
        $nd = ($d + $weight[$v]);
        if (($nd < $dist[$v])) {
            $dist[$v] = $nd;
            push($nd, $v);
        }
    }
}
$check = (($dist[$target] * 1000) + ($pops % 1000));
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

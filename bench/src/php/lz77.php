<?php
const DATA_SIZE = (1 << 20);
const WORDS = 512;
const HASH_SIZE = 65536;
const WINDOW = 32768;
const MIN_MATCH = 4;
const MAX_MATCH = 258;
const MAX_CHAIN = 32;
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

$words = [];
for ($k = 0; $k < WORDS; $k += 1) {
    $length = (2 + (rnd() % 8));
    $words[] = array_map(fn($_) => (97 + (rnd() % 26)), range(0, $length - 1));
}
$n = DATA_SIZE;
$data = array_fill(0, $n, 0);
$pos = 0;
while (($pos < $n)) {
    $w = $words[(rnd() % WORDS)];
    foreach ($w as $b) {
        if (($pos >= $n)) {
            break;
        }
        $data[$pos] = $b;
        $pos += 1;
    }
    if (($pos < $n)) {
        $data[$pos] = 32;
        $pos += 1;
    }
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$head = array_fill(0, HASH_SIZE, (-1));
$prev = array_fill(0, WINDOW, (-1));

function hash_at($d, $p) {
    return ((((((($d[$p] * 33) + $d[($p + 1)]) * 33) + $d[($p + 2)]) * 33) + $d[($p + 3)]) % HASH_SIZE);
}

$comp = array_fill(0, (($n * 2) + 16), 0);
$csize = 0;
$i = 0;
while ((($i + MIN_MATCH) <= $n)) {
    $best = 0;
    $dist = 0;
    $limit = ((($n - $i) < MAX_MATCH) ? ($n - $i) : MAX_MATCH);
    $h = hash_at($data, $i);
    $cand = $head[$h];
    $chain = 0;
    while ((($cand >= 0) && (($i - $cand) < WINDOW) && ($chain < MAX_CHAIN))) {
        $l = 0;
        while ((($l < $limit) && ($data[($cand + $l)] == $data[($i + $l)]))) {
            $l += 1;
        }
        if (($l > $best)) {
            $best = $l;
            $dist = ($i - $cand);
            if (($l == $limit)) {
                break;
            }
        }
        $cand = $prev[($cand % WINDOW)];
        $chain += 1;
    }
    $prev[($i % WINDOW)] = $head[$h];
    $head[$h] = $i;
    if (($best >= MIN_MATCH)) {
        $comp[$csize] = 1;
        $comp[($csize + 1)] = ($best - MIN_MATCH);
        $comp[($csize + 2)] = (($dist - 1) % 256);
        $comp[($csize + 3)] = intdiv(($dist - 1), 256);
        $csize += 4;
        for ($p = ($i + 1); $p < ($i + $best); $p += 1) {
            if ((($p + MIN_MATCH) <= $n)) {
                $hp = hash_at($data, $p);
                $prev[($p % WINDOW)] = $head[$hp];
                $head[$hp] = $p;
            }
        }
        $i += $best;
    } else {
        $comp[$csize] = 0;
        $comp[($csize + 1)] = $data[$i];
        $csize += 2;
        $i += 1;
    }
}
while (($i < $n)) {
    $comp[$csize] = 0;
    $comp[($csize + 1)] = $data[$i];
    $csize += 2;
    $i += 1;
}
$out = array_fill(0, $n, 0);
$o = 0;
$c = 0;
while (($c < $csize)) {
    if (($comp[$c] == 0)) {
        $out[$o] = $comp[($c + 1)];
        $o += 1;
        $c += 2;
    } else {
        $length = ($comp[($c + 1)] + MIN_MATCH);
        $back = (($comp[($c + 2)] + ($comp[($c + 3)] * 256)) + 1);
        for ($k = 0; $k < $length; $k += 1) {
            $out[$o] = $out[($o - $back)];
            $o += 1;
        }
        $c += 4;
    }
}
$same = ($o == $n);
$k = 0;
while (($same && ($k < $n))) {
    if (($out[$k] != $data[$k])) {
        $same = false;
    }
    $k += 1;
}
$hc = 0;
for ($k = 0; $k < $csize; $k += 1) {
    $hc = ((($hc * 31) + $comp[$k]) % 1000003);
}
$check = ($same ? (($csize * 1000003) + $hc) : 0);
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

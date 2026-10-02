<?php
function sorted_keys($keys) { sort($keys, SORT_STRING); return $keys; }
const ROWS = 400000;
const REGIONS = ["EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"];
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

$lines = [];
for ($j = 0; $j < ROWS; $j += 1) {
    $region = REGIONS[(rnd() % 8)];
    $y = (2024 + (rnd() % 3));
    $m = (1 + (rnd() % 12));
    $d = (1 + (rnd() % 28));
    $qty = (1 + (rnd() % 50));
    $cents = (100 + (rnd() % 99900));
    $lines[] = sprintf("%d,%s,%d-%02d-%02d,%d,%d.%02d", $j, $region, $y, $m, $d, $qty, intdiv($cents, 100), ($cents % 100));
}
$text = implode("\n", $lines);

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$n = strlen($text);
$agg = [];
$pos = 0;
$rows = 0;
while (($pos < $n)) {
    $eol = $pos;
    while ((($eol < $n) && (ord($text[$eol]) != 10))) {
        $eol += 1;
    }
    $p = $pos;
    while ((($p < $eol) && (ord($text[$p]) != 44))) {
        $p += 1;
    }
    $p += 1;
    $rs = $p;
    while ((($p < $eol) && (ord($text[$p]) != 44))) {
        $p += 1;
    }
    $region = substr($text, $rs, $p - $rs);
    $p += 1;
    while ((($p < $eol) && (ord($text[$p]) != 44))) {
        $p += 1;
    }
    $p += 1;
    $qty = 0;
    while ((($p < $eol) && (ord($text[$p]) != 44))) {
        $qty = (($qty * 10) + (ord($text[$p]) - 48));
        $p += 1;
    }
    $p += 1;
    $ip = 0;
    while ((($p < $eol) && (ord($text[$p]) != 46))) {
        $ip = (($ip * 10) + (ord($text[$p]) - 48));
        $p += 1;
    }
    $p += 1;
    $fr = 0;
    while (($p < $eol)) {
        $fr = (($fr * 10) + (ord($text[$p]) - 48));
        $p += 1;
    }
    $price = ($ip + ($fr / 100.0));
    $e = &$agg[$region];
    if (($e == null)) {
        $agg[$region] = [1, $qty, ($qty * $price), $price];
    } else {
        $e[0] += 1;
        $e[1] += $qty;
        $e[2] += ($qty * $price);
        if (($price > $e[3])) {
            $e[3] = $price;
        }
    }
    $rows += 1;
    $pos = ($eol + 1);
}
$keys = sorted_keys(array_keys($agg));
$check = $rows;
for ($k = 0; $k < count($keys); $k += 1) {
    $e = &$agg[$keys[$k]];
    $check += (($k + 1) * ((int) ((($e[2] * 100.0) + 0.5)) % 1000003));
    $check += (($e[0] + $e[1]) + (int) ((($e[3] * 100.0) + 0.5)));
}
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

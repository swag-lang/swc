<?php
const DICT = 6000;
const QUERIES = 40;
const MAXLEN = 3;
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

function make_word($i) {
    $n = ($i + 1);
    $length = (4 + ($i % 7));
    $out = [];
    for ($k = 0; $k < $length; $k += 1) {
        $out[] = chr((97 + ($n % 26)));
        $n = (intdiv($n, 26) + (7 * $k));
    }
    return implode("", $out);
}

$words = [];
for ($i = 0; $i < DICT; $i += 1) {
    $words[] = make_word($i);
}
$queries = [];
for ($q = 0; $q < QUERIES; $q += 1) {
    $w = str_split($words[(rnd() % DICT)]);
    for ($m = 0; $m < 2; $m += 1) {
        $p = (rnd() % count($w));
        $op = (rnd() % 3);
        $c = chr((97 + (rnd() % 26)));
        if (($op == 0)) {
            $w[$p] = $c;
        } else {
            if (($op == 1)) {
                if ((count($w) > 2)) {
                    array_splice($w, $p, 1);
                }
            } else {
                array_splice($w, $p, 0, [$c]);
            }
        }
    }
    $queries[] = implode("", $w);
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$row0 = array_fill(0, 64, 0);
$row1 = array_fill(0, 64, 0);
$check = 0;
for ($q = 0; $q < QUERIES; $q += 1) {
    $a = $queries[$q];
    $la = strlen($a);
    $best = (1 << 30);
    $bestIdx = (-1);
    for ($i = 0; $i < DICT; $i += 1) {
        $b = $words[$i];
        $lb = strlen($b);
        $d = ($la - $lb);
        if (($d < 0)) {
            $d = (-$d);
        }
        if (($d > MAXLEN)) {
            continue;
        }
        for ($j = 0; $j < ($lb + 1); $j += 1) {
            $row0[$j] = $j;
        }
        for ($x = 0; $x < $la; $x += 1) {
            $row1[0] = ($x + 1);
            $ca = $a[$x];
            for ($y = 0; $y < $lb; $y += 1) {
                $cost = (($ca == $b[$y]) ? 0 : 1);
                $v = ($row0[$y] + $cost);
                $v2 = ($row0[($y + 1)] + 1);
                if (($v2 < $v)) {
                    $v = $v2;
                }
                $v2 = ($row1[$y] + 1);
                if (($v2 < $v)) {
                    $v = $v2;
                }
                $row1[($y + 1)] = $v;
            }
            for ($j = 0; $j < ($lb + 1); $j += 1) {
                $row0[$j] = $row1[$j];
            }
        }
        $dd = $row0[$lb];
        if (($dd < $best)) {
            $best = $dd;
            $bestIdx = $i;
        }
    }
    $check += (($best * 31) + $bestIdx);
}
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

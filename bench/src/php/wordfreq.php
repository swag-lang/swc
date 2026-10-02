<?php
const VOCAB = 5000;
const WORDS = 2000000;
$seed = 12345;

function rnd() {
    global $seed;
    $seed = (($seed * 16807) % 2147483647);
    return $seed;
}

function make_word($i) {
    $n = ($i + 1);
    $length = (3 + ($i % 6));
    $out = [];
    for ($k = 0; $k < $length; $k += 1) {
        $out[] = chr((97 + ($n % 26)));
        $n = (intdiv($n, 26) + (7 * $k));
    }
    return implode("", $out);
}

$vocab = [];
for ($i = 0; $i < VOCAB; $i += 1) {
    $vocab[] = make_word($i);
}
$pieces = [];
for ($j = 0; $j < WORDS; $j += 1) {
    $idx = (rnd() % VOCAB);
    $pieces[] = $vocab[$idx];
    $pieces[] = (((($j + 1) % 12) == 0) ? "\n" : " ");
}
$text = implode("", $pieces);

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$counts = [];
$n = strlen($text);
$i = 0;
$start = (-1);
while (($i < $n)) {
    $c = ord($text[$i]);
    if ((97 <= $c && $c <= 122)) {
        if (($start < 0)) {
            $start = $i;
        }
    } else {
        if (($start >= 0)) {
            $tok = substr($text, $start, $i - $start);
            $counts[$tok] = (($counts[$tok] ?? 0) + 1);
            $start = (-1);
        }
    }
    $i += 1;
}
if (($start >= 0)) {
    $tok = substr($text, $start, $n - $start);
    $counts[$tok] = (($counts[$tok] ?? 0) + 1);
}
$items = [];
foreach ($counts as $w => $c) {
    $items[] = [$c, $w];
}
usort($items, fn($a, $b) => ($b[0] <=> $a[0]) ?: strcmp($a[1], $b[1]));
$check = (count($counts) * 7);
for ($k = 0; $k < 20; $k += 1) {
    $check += (($k + 1) * $items[$k][0]);
}
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";

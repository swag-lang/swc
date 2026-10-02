<?php
const MIN_DEPTH = 4;
const MAX_DEPTH = 12;
class Node {
    public $left;
    public $right;

    function __construct($left, $right) {
        $this->left = $left;
        $this->right = $right;
    }

}

function bottom_up($depth) {
    if (($depth > 0)) {
        return new Node(bottom_up(($depth - 1)), bottom_up(($depth - 1)));
    }
    return new Node(null, null);
}

function check($node) {
    if (($node->left == null)) {
        return 1;
    }
    return ((1 + check($node->left)) + check($node->right));
}

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
$total = 0;
$stretch = bottom_up((MAX_DEPTH + 1));
$total += check($stretch);
$stretch = null;
$long_lived = bottom_up(MAX_DEPTH);
for ($d = MIN_DEPTH; $d < (MAX_DEPTH + 1); $d += 2) {
    $iterations = (1 << ((MAX_DEPTH - $d) + MIN_DEPTH));
    for ($i = 0; $i < $iterations; $i += 1) {
        $tree = bottom_up($d);
        $total += check($tree);
        $tree = null;
    }
}
$total += check($long_lived);
$long_lived = null;
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $total, (($t1 - $t0) * 1000.0)) . "\n";

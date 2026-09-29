const MIN_DEPTH = 4;
const MAX_DEPTH = 12;

class Node {
    constructor(left, right) {
        this.left = left;
        this.right = right;
    }
}

function bottomUp(depth) {
    if (depth > 0) return new Node(bottomUp(depth - 1), bottomUp(depth - 1));
    return new Node(null, null);
}

function check(node) {
    if (node.left === null) return 1;
    return 1 + check(node.left) + check(node.right);
}

// ---- timed work (no input data) ----
const t0 = performance.now();

let total = 0;

let stretch = bottomUp(MAX_DEPTH + 1);
total += check(stretch);
stretch = null;

let longLived = bottomUp(MAX_DEPTH);

for (let d = MIN_DEPTH; d <= MAX_DEPTH; d += 2) {
    const iterations = 1 << (MAX_DEPTH - d + MIN_DEPTH);
    for (let i = 0; i < iterations; i++) {
        let tree = bottomUp(d);
        total += check(tree);
        tree = null;
    }
}

total += check(longLived);
longLived = null;

const t1 = performance.now();
console.log("CHECK=" + total + " MS=" + (t1 - t0).toFixed(3));

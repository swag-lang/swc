package main

import common "common"

MIN_DEPTH :: u32(4)
MAX_DEPTH :: u32(12)

Node :: struct {
    left:  ^Node,
    right: ^Node,
}

bottom_up :: proc(depth: u32) -> ^Node {
    node := new(Node)
    if depth > 0 {
        node.left = bottom_up(depth - 1)
        node.right = bottom_up(depth - 1)
    } else {
        node.left = nil
        node.right = nil
    }
    return node
}

check :: proc(node: ^Node) -> u64 {
    if node.left == nil {
        return 1
    }
    return 1 + check(node.left) + check(node.right)
}

release :: proc(node: ^Node) {
    if node.left != nil {
        release(node.left)
        release(node.right)
    }
    free(node)
}

main :: proc() {
    // Timed work: there is no input data.
    t0: f64 = common.now()
    total: u64 = 0

    stretch := bottom_up(MAX_DEPTH + 1)
    total += check(stretch)
    release(stretch)

    long_lived := bottom_up(MAX_DEPTH)

    for d := MIN_DEPTH; d <= MAX_DEPTH; d += 2 {
        iterations: u64 = u64(1) << (MAX_DEPTH - d + MIN_DEPTH)
        for i: u64 = 0; i < iterations; i += 1 {
            tree := bottom_up(d)
            total += check(tree)
            release(tree)
        }
    }

    total += check(long_lived)
    release(long_lived)

    t1: f64 = common.now()
    common.report(total, t0, t1)
}

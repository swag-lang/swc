// Same tree shapes, allocation pattern and timed region as the other benchmark ports.
const std = @import("std");
const common = @import("common.zig");
const now = common.now;
const report = common.report;

const MIN_DEPTH: u32 = 4;
const MAX_DEPTH: u32 = 12;

const Node = struct {
    left: ?*Node,
    right: ?*Node,
};

const allocator = std.heap.c_allocator;

fn bottomUp(depth: u32) *Node {
    const node = allocator.create(Node) catch @panic("oom");
    if (depth > 0) {
        node.* = .{ .left = bottomUp(depth - 1), .right = bottomUp(depth - 1) };
    } else {
        node.* = .{ .left = null, .right = null };
    }
    return node;
}

fn check(node: *const Node) u64 {
    if (node.left) |left| {
        return 1 + check(left) + check(node.right.?);
    }
    return 1;
}

fn release(node: *Node) void {
    if (node.left) |left| {
        release(left);
        release(node.right.?);
    }
    allocator.destroy(node);
}

pub fn main() void {
    // Timed work: there is no input data.
    const t0: f64 = now();
    var total: u64 = 0;

    const stretch = bottomUp(MAX_DEPTH + 1);
    total += check(stretch);
    release(stretch);

    const longLived = bottomUp(MAX_DEPTH);

    var d: u32 = MIN_DEPTH;
    while (d <= MAX_DEPTH) : (d += 2) {
        const iterations: u64 = @as(u64, 1) << @intCast(MAX_DEPTH - d + MIN_DEPTH);
        var i: u64 = 0;
        while (i < iterations) : (i += 1) {
            const tree = bottomUp(d);
            total += check(tree);
            release(tree);
        }
    }

    total += check(longLived);
    release(longLived);

    const t1: f64 = now();
    report(total, t0, t1);
}

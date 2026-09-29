// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const free = common.free;

const N: i64 = 300000;

fn swap(a: [*]u64, i: i64, j: i64) void {
    const t = a[@intCast(i)];
    a[@intCast(i)] = a[@intCast(j)];
    a[@intCast(j)] = t;
}

fn qsort(a: [*]u64, lo_in: i64, hi_in: i64) void {
    var lo = lo_in;
    var hi = hi_in;
    while (hi - lo > 16) {
        const mid = lo + @divTrunc(hi - lo, 2);
        if (a[@intCast(mid)] < a[@intCast(lo)]) swap(a, lo, mid);
        if (a[@intCast(hi)] < a[@intCast(lo)]) swap(a, lo, hi);
        if (a[@intCast(hi)] < a[@intCast(mid)]) swap(a, mid, hi);

        const pivot = a[@intCast(mid)];
        var i = lo;
        var j = hi;
        while (true) {
            while (a[@intCast(i)] < pivot) i += 1;
            while (a[@intCast(j)] > pivot) j -= 1;
            if (i <= j) {
                swap(a, i, j);
                i += 1;
                j -= 1;
            }
            if (i > j) break;
        }

        // Recurse into the smaller side, loop on the larger one.
        if (j - lo < hi - i) {
            qsort(a, lo, j);
            lo = i;
        } else {
            qsort(a, i, hi);
            hi = j;
        }
    }

    var i = lo + 1;
    while (i <= hi) : (i += 1) {
        const v = a[@intCast(i)];
        var j = i - 1;
        while (j >= lo and a[@intCast(j)] > v) {
            a[@intCast(j + 1)] = a[@intCast(j)];
            j -= 1;
        }
        a[@intCast(j + 1)] = v;
    }
}

pub fn main() void {
    const a: [*]u64 = @ptrCast(@alignCast(xalloc(N * @sizeOf(u64))));
    {
        var i: i64 = 0;
        while (i < N) : (i += 1) {
            a[@intCast(i)] = rnd();
        }
    }

    // Timed work starts after data generation.
    const t0: f64 = now();

    qsort(a, 0, N - 1);

    var sorted = true;
    {
        var i: i64 = 1;
        while (i < N) : (i += 1) {
            if (a[@intCast(i - 1)] > a[@intCast(i)]) sorted = false;
        }
    }

    var check: u64 = 0;
    if (sorted) {
        var i: i64 = 0;
        while (i < N) : (i += 1) {
            check += (a[@intCast(i)] % 1000) * @as(u64, @intCast(@rem(i, 7) + 1));
        }
    }

    const t1: f64 = now();
    report(check, t0, t1);

    free(a);
    return;
}

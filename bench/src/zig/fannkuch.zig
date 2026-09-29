// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const free = common.free;

const N: usize = 9;

pub fn main() void {
    const perm: [*]usize = @ptrCast(@alignCast(xalloc(N * @sizeOf(usize))));
    const perm1: [*]usize = @ptrCast(@alignCast(xalloc(N * @sizeOf(usize))));
    const count: [*]usize = @ptrCast(@alignCast(xalloc(N * @sizeOf(usize))));

    // Timed work starts after data generation.
    const t0: f64 = now();

    {
        var i: usize = 0;
        while (i < N) : (i += 1) {
            perm1[i] = i;
        }
    }

    var checksum: i64 = 0;
    var maxFlips: i64 = 0;
    var permCount: i64 = 0;
    var r: usize = N;

    while (true) {
        while (r != 1) {
            count[r - 1] = r;
            r -= 1;
        }

        {
            var i: usize = 0;
            while (i < N) : (i += 1) {
                perm[i] = perm1[i];
            }
        }

        var flips: i64 = 0;
        var k: usize = perm[0];
        while (k != 0) {
            var i: usize = 0;
            var j: usize = k;
            while (i < j) {
                const t = perm[i];
                perm[i] = perm[j];
                perm[j] = t;
                i += 1;
                j -= 1;
            }
            flips += 1;
            k = perm[0];
        }

        if (flips > maxFlips) {
            maxFlips = flips;
        }
        if (@rem(permCount, 2) == 0) {
            checksum += flips;
        } else {
            checksum -= flips;
        }

        // Rotate the prefix to reach the next permutation.
        var done = false;
        while (true) {
            if (r == N) {
                done = true;
                break;
            }
            const perm0 = perm1[0];
            var i: usize = 0;
            while (i < r) : (i += 1) {
                perm1[i] = perm1[i + 1];
            }
            perm1[r] = perm0;
            count[r] -= 1;
            if (count[r] > 0) {
                break;
            }
            r += 1;
        }
        if (done) {
            break;
        }
        permCount += 1;
    }

    const check: u64 = @intCast(checksum * 1000 + maxFlips);

    const t1: f64 = now();
    report(check, t0, t1);

    free(count);
    free(perm1);
    free(perm);
    return;
}

// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const free = common.free;

const NWORDS: u64 = 4194304;
const M32: u64 = 0xFFFFFFFF;
fn add32(left: u32, right: u32) u32 {
    return @as(u32, @intCast(((@as(u64, @intCast(left)) + right) & M32)));
}

fn rol(x: u32, k: i32) u32 {
    return @as(u32, @intCast((((x << @intCast(k)) | (x >> @intCast((32 - k)))) & M32)));
}

fn quarterRound(state: [*]u32, a: usize, b: usize, c: usize, d: usize) void {
    state[a] = add32(state[a], state[b]);
    state[d] ^= state[a];
    state[d] = rol(state[d], 16);
    state[c] = add32(state[c], state[d]);
    state[b] ^= state[c];
    state[b] = rol(state[b], 12);
    state[a] = add32(state[a], state[b]);
    state[d] ^= state[a];
    state[d] = rol(state[d], 8);
    state[c] = add32(state[c], state[d]);
    state[b] ^= state[c];
    state[b] = rol(state[b], 7);
}

pub fn main() void {
    const data: [*]u32 = @ptrCast(@alignCast(xalloc((NWORDS * 4))));
    {
        var i: u64 = 0;
        while ((i < NWORDS)) : (i += 1) {
            data[i] = @as(u32, @intCast((rnd() & M32)));
        }
    }
    var key: [8]u32 = undefined;
    {
        var i: u64 = 0;
        while ((i < 8)) : (i += 1) {
            key[i] = @as(u32, @intCast((rnd() & M32)));
        }
    }
    var nonce: [3]u32 = undefined;
    {
        var i: u64 = 0;
        while ((i < 3)) : (i += 1) {
            nonce[i] = @as(u32, @intCast((rnd() & M32)));
        }
    }
    // Timed work starts after data generation.
    const t0: f64 = now();
    var initial: [16]u32 = undefined;
    initial[0] = 0x61707865;
    initial[1] = 0x3320646E;
    initial[2] = 0x79622D32;
    initial[3] = 0x6B206574;
    {
        var i: usize = 0;
        while ((i < 8)) : (i += 1) {
            initial[(4 + i)] = key[i];
        }
    }
    {
        var i: usize = 0;
        while ((i < 3)) : (i += 1) {
            initial[(13 + i)] = nonce[i];
        }
    }
    var offset: u64 = 0;
    var counter: u32 = 1;
    while ((offset < NWORDS)) {
        initial[12] = counter;
        var state: [16]u32 = undefined;
        {
            var i: usize = 0;
            while ((i < 16)) : (i += 1) {
                state[i] = initial[i];
            }
        }
        {
            var r: i32 = 0;
            while ((r < 10)) : (r += 1) {
                quarterRound(&state, 0, 4, 8, 12);
                quarterRound(&state, 1, 5, 9, 13);
                quarterRound(&state, 2, 6, 10, 14);
                quarterRound(&state, 3, 7, 11, 15);
                quarterRound(&state, 0, 5, 10, 15);
                quarterRound(&state, 1, 6, 11, 12);
                quarterRound(&state, 2, 7, 8, 13);
                quarterRound(&state, 3, 4, 9, 14);
            }
        }
        {
            var i: u64 = 0;
            while ((i < 16)) : (i += 1) {
                data[(offset + i)] ^= add32(state[i], initial[i]);
            }
        }
        offset += 16;
        counter += 1;
    }
    var check: u64 = 0;
    {
        var i: u64 = 0;
        while ((i < NWORDS)) : (i += 1) {
            check ^= ((@as(u64, @intCast(data[i])) + i) & M32);
        }
    }
    const t1: f64 = now();
    report(check, t0, t1);
    free(data);
    return;
}


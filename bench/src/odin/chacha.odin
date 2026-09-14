package main

import common "common"

NWORDS :: u64(4194304)
M32 :: 0xFFFFFFFF
add32 :: proc(left: u32, right: u32) -> u32 {
    return u32(((u64(left) + u64(right)) & M32))
}

rol :: proc(x: u32, k: u32) -> u32 {
    return u32((((x << k) | (x >> (32 - k))) & M32))
}

quarterRound :: proc(state: [^]u32, a: i32, b: i32, c: i32, d: i32) {
    state[a] = add32(state[a], state[b])
    state[d] ~= state[a]
    state[d] = rol(state[d], 16)
    state[c] = add32(state[c], state[d])
    state[b] ~= state[c]
    state[b] = rol(state[b], 12)
    state[a] = add32(state[a], state[b])
    state[d] ~= state[a]
    state[d] = rol(state[d], 8)
    state[c] = add32(state[c], state[d])
    state[b] ~= state[c]
    state[b] = rol(state[b], 7)
}

main :: proc() {
    data: [^]u32 = ([^]u32)(common.xalloc((NWORDS * 4)))
    for i: u64 = 0; (i < NWORDS); i += 1 {
        data[i] = u32((common.rnd() & M32))
    }
    key: [8]u32
    for i: u64 = 0; (i < 8); i += 1 {
        key[i] = u32((common.rnd() & M32))
    }
    nonce: [3]u32
    for i: u64 = 0; (i < 3); i += 1 {
        nonce[i] = u32((common.rnd() & M32))
    }
    // Timed work starts after data generation.
    t0: f64 = common.now()
    initial: [16]u32
    initial[0] = 0x61707865
    initial[1] = 0x3320646E
    initial[2] = 0x79622D32
    initial[3] = 0x6B206574
    for i: i32 = 0; (i < 8); i += 1 {
        initial[(4 + i)] = key[i]
    }
    for i: i32 = 0; (i < 3); i += 1 {
        initial[(13 + i)] = nonce[i]
    }
    offset: u64 = 0
    counter: u32 = 1
    for (offset < NWORDS) {
        initial[12] = counter
        state: [16]u32
        for i: i32 = 0; (i < 16); i += 1 {
            state[i] = initial[i]
        }
        for r: i32 = 0; (r < 10); r += 1 {
            quarterRound(raw_data(state[:]), 0, 4, 8, 12)
            quarterRound(raw_data(state[:]), 1, 5, 9, 13)
            quarterRound(raw_data(state[:]), 2, 6, 10, 14)
            quarterRound(raw_data(state[:]), 3, 7, 11, 15)
            quarterRound(raw_data(state[:]), 0, 5, 10, 15)
            quarterRound(raw_data(state[:]), 1, 6, 11, 12)
            quarterRound(raw_data(state[:]), 2, 7, 8, 13)
            quarterRound(raw_data(state[:]), 3, 4, 9, 14)
        }
        for i: u64 = 0; (i < 16); i += 1 {
            data[(offset + i)] ~= add32(state[i], initial[i])
        }
        offset += 16
        counter += 1
    }
    check: u64 = 0
    for i: u64 = 0; (i < NWORDS); i += 1 {
        check ~= ((u64(data[i]) + i) & M32)
    }
    t1: f64 = common.now()
    common.report(check, t0, t1)
    common.free(data)
    return
}


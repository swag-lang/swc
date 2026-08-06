use std::time::Instant;

const SIZE: u64 = 262144; // 32-bit words, one mebibyte of key stream
const M32: u64 = 0xFFFFFFFF;

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

#[inline(always)]
fn add32(left: u32, right: u32) -> u32 {
    (((left as u64) + right as u64) & M32) as u32
}

#[inline(always)]
fn rol(x: u32, k: u32) -> u32 {
    ((x << k) | (x >> (32 - k))) & M32 as u32
}

#[inline(always)]
fn quarter_round(state: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize) {
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

fn main() {
    // ---- data generation (not timed) ----
    let mut data: Vec<u32> = vec![0; SIZE as usize];
    for i in 0..SIZE as usize {
        data[i] = (rnd() & M32) as u32;
    }

    let mut key = [0u32; 8];
    for i in 0..8 {
        key[i] = (rnd() & M32) as u32;
    }

    let mut nonce = [0u32; 3];
    for i in 0..3 {
        nonce[i] = (rnd() & M32) as u32;
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut initial = [0u32; 16];
    initial[0] = 0x61707865;
    initial[1] = 0x3320646E;
    initial[2] = 0x79622D32;
    initial[3] = 0x6B206574;
    for i in 0..8 {
        initial[4 + i] = key[i];
    }
    for i in 0..3 {
        initial[13 + i] = nonce[i];
    }

    let mut offset: usize = 0;
    let mut counter: u32 = 1;
    while (offset as u64) < SIZE {
        initial[12] = counter;

        let mut state = initial;
        for _ in 0..10 {
            quarter_round(&mut state, 0, 4, 8, 12);
            quarter_round(&mut state, 1, 5, 9, 13);
            quarter_round(&mut state, 2, 6, 10, 14);
            quarter_round(&mut state, 3, 7, 11, 15);
            quarter_round(&mut state, 0, 5, 10, 15);
            quarter_round(&mut state, 1, 6, 11, 12);
            quarter_round(&mut state, 2, 7, 8, 13);
            quarter_round(&mut state, 3, 4, 9, 14);
        }

        for i in 0..16 {
            data[offset + i] ^= add32(state[i], initial[i]);
        }

        offset += 16;
        counter = counter.wrapping_add(1);
    }

    let mut check: u64 = 0;
    for i in 0..SIZE as usize {
        check ^= ((data[i] as u64) + i as u64) & M32;
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

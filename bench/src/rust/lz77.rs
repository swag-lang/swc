use std::time::Instant;

const DATA_SIZE: usize = 1 << 20;
const WORDS: usize = 512;
const HASH_SIZE: usize = 65536;
const WINDOW: i64 = 32768;
const MIN_MATCH: i64 = 4;
const MAX_MATCH: i64 = 258;
const MAX_CHAIN: i64 = 32;

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

#[inline]
fn hash_at(d: &[u8], p: i64) -> usize {
    let p = p as usize;
    (((d[p] as usize * 33 + d[p + 1] as usize) * 33 + d[p + 2] as usize) * 33 + d[p + 3] as usize)
        % HASH_SIZE
}

fn main() {
    // ---- data generation (not timed) ----
    let mut letters = vec![0u8; WORDS * 10];
    let mut word_start = vec![0usize; WORDS];
    let mut word_len = vec![0usize; WORDS];
    let mut used = 0usize;
    for k in 0..WORDS {
        let len = 2 + (rnd() % 8) as usize;
        word_start[k] = used;
        word_len[k] = len;
        for j in 0..len {
            letters[used + j] = (97 + rnd() % 26) as u8;
        }
        used += len;
    }

    let n = DATA_SIZE as i64;
    let mut data = vec![0u8; DATA_SIZE];
    let mut pos = 0usize;
    while pos < DATA_SIZE {
        let w = (rnd() % WORDS as u64) as usize;
        let mut j = 0;
        while j < word_len[w] && pos < DATA_SIZE {
            data[pos] = letters[word_start[w] + j];
            pos += 1;
            j += 1;
        }
        if pos < DATA_SIZE {
            data[pos] = b' ';
            pos += 1;
        }
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut head = vec![-1i64; HASH_SIZE];
    let mut prev = vec![-1i64; WINDOW as usize];

    let mut comp = vec![0u8; DATA_SIZE * 2 + 16];
    let mut csize = 0usize;

    let mut i: i64 = 0;
    while i + MIN_MATCH <= n {
        let mut best: i64 = 0;
        let mut dist: i64 = 0;
        let limit = if n - i < MAX_MATCH { n - i } else { MAX_MATCH };
        let h = hash_at(&data, i);
        let mut cand = head[h];
        let mut chain: i64 = 0;
        while cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN {
            let mut l: i64 = 0;
            while l < limit && data[(cand + l) as usize] == data[(i + l) as usize] {
                l += 1;
            }
            if l > best {
                best = l;
                dist = i - cand;
                if l == limit {
                    break;
                }
            }
            cand = prev[(cand % WINDOW) as usize];
            chain += 1;
        }

        prev[(i % WINDOW) as usize] = head[h];
        head[h] = i;

        if best >= MIN_MATCH {
            comp[csize] = 1;
            comp[csize + 1] = (best - MIN_MATCH) as u8;
            comp[csize + 2] = ((dist - 1) % 256) as u8;
            comp[csize + 3] = ((dist - 1) / 256) as u8;
            csize += 4;
            for p in i + 1..i + best {
                if p + MIN_MATCH <= n {
                    let hp = hash_at(&data, p);
                    prev[(p % WINDOW) as usize] = head[hp];
                    head[hp] = p;
                }
            }
            i += best;
        } else {
            comp[csize] = 0;
            comp[csize + 1] = data[i as usize];
            csize += 2;
            i += 1;
        }
    }

    while i < n {
        comp[csize] = 0;
        comp[csize + 1] = data[i as usize];
        csize += 2;
        i += 1;
    }

    // ---- decompress and verify ----
    let mut out = vec![0u8; DATA_SIZE];
    let mut o = 0usize;
    let mut c = 0usize;
    while c < csize {
        if comp[c] == 0 {
            out[o] = comp[c + 1];
            o += 1;
            c += 2;
        } else {
            let len = comp[c + 1] as usize + MIN_MATCH as usize;
            let back = comp[c + 2] as usize + comp[c + 3] as usize * 256 + 1;
            for _ in 0..len {
                out[o] = out[o - back];
                o += 1;
            }
            c += 4;
        }
    }

    let mut same = o == DATA_SIZE;
    let mut k = 0;
    while same && k < DATA_SIZE {
        if out[k] != data[k] {
            same = false;
        }
        k += 1;
    }

    let mut hc: u64 = 0;
    for k in 0..csize {
        hc = (hc * 31 + comp[k] as u64) % 1000003;
    }

    let check = if same { csize as u64 * 1000003 + hc } else { 0 };

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

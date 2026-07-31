use std::time::Instant;

const DICT: u64 = 6000;
const QUERIES: u64 = 40;
const MAXLEN: u64 = 3;

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

fn main() {
    // ---- data generation (not timed) ----
    let mut bytes = vec![0u8; (DICT * 16) as usize];
    let mut word_off = vec![0u64; DICT as usize];
    let mut word_len = vec![0u64; DICT as usize];

    let mut wp: u64 = 0;
    for i in 0..DICT {
        let mut n = i + 1;
        let l = 4 + (i % 7);
        word_off[i as usize] = wp;
        word_len[i as usize] = l;
        for k in 0..l {
            bytes[wp as usize] = (97 + (n % 26)) as u8;
            wp += 1;
            n = n / 26 + 7 * k;
        }
    }

    let mut q_bytes = vec![0u8; (QUERIES * 32) as usize];
    let mut q_off = vec![0u64; QUERIES as usize];
    let mut q_len = vec![0u64; QUERIES as usize];

    let mut qp: u64 = 0;
    for q in 0..QUERIES as usize {
        let mut tmp = [0u8; 32];
        let src = rnd() % DICT;
        let mut nw = word_len[src as usize];
        for i in 0..nw as usize {
            tmp[i] = bytes[word_off[src as usize] as usize + i];
        }

        for _ in 0..2 {
            let p = rnd() % nw;
            let op = rnd() % 3;
            let c = (97 + (rnd() % 26)) as u8;
            if op == 0 {
                tmp[p as usize] = c;
            } else if op == 1 {
                if nw > 2 {
                    let mut i = p;
                    while i + 1 < nw {
                        tmp[i as usize] = tmp[(i + 1) as usize];
                        i += 1;
                    }
                    nw -= 1;
                }
            } else {
                let mut i = nw;
                while i > p {
                    tmp[i as usize] = tmp[(i - 1) as usize];
                    i -= 1;
                }
                tmp[p as usize] = c;
                nw += 1;
            }
        }

        q_off[q] = qp;
        q_len[q] = nw;
        for i in 0..nw as usize {
            q_bytes[qp as usize] = tmp[i];
            qp += 1;
        }
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut row0 = [0u64; 64];
    let mut row1 = [0u64; 64];

    let mut check: i64 = 0;
    for q in 0..QUERIES as usize {
        let ao = q_off[q];
        let la = q_len[q];
        let mut best: u64 = 1073741824;
        let mut best_idx: i64 = -1;

        for i in 0..DICT as usize {
            let bo = word_off[i];
            let lb = word_len[i];
            let d = if la > lb { la - lb } else { lb - la };
            if d > MAXLEN {
                continue;
            }

            for j in 0..(lb + 1) as usize {
                row0[j] = j as u64;
            }

            for x in 0..la {
                row1[0] = x + 1;
                let ca = q_bytes[(ao + x) as usize];
                for y in 0..lb as usize {
                    let cost = if ca == bytes[bo as usize + y] { 0 } else { 1 };
                    let mut v = row0[y] + cost;
                    let mut v2 = row0[y + 1] + 1;
                    if v2 < v {
                        v = v2;
                    }
                    v2 = row1[y] + 1;
                    if v2 < v {
                        v = v2;
                    }
                    row1[y + 1] = v;
                }
                for j in 0..(lb + 1) as usize {
                    row0[j] = row1[j];
                }
            }

            let dd = row0[lb as usize];
            if dd < best {
                best = dd;
                best_idx = i as i64;
            }
        }

        check += best as i64 * 31 + best_idx;
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check as u64, ms);
}

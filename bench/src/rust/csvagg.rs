use std::time::Instant;

const ROWS: u64 = 400000;

const REGIONS: [&str; 8] = [
    "EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH",
];

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

struct ByteMap {
    key_off: Vec<u64>,
    key_len: Vec<u64>,
    val: Vec<u64>,
    used: Vec<u8>,
    mask: u64,
    count: u64,
}

impl ByteMap {
    fn new(capacity: u64) -> ByteMap {
        let c = capacity as usize;
        ByteMap {
            key_off: vec![0; c],
            key_len: vec![0; c],
            val: vec![0; c],
            used: vec![0; c],
            mask: capacity - 1,
            count: 0,
        }
    }

    fn probe(&self, base: &[u8], off: u64, len: u64) -> u64 {
        let mut h: u64 = 2166136261;
        for i in 0..len {
            h ^= base[(off + i) as usize] as u64;
            h = (h.wrapping_mul(16777619)) & 0xFFFFFFFF;
        }

        let mut idx = h & self.mask;
        while self.used[idx as usize] != 0 {
            if self.key_len[idx as usize] == len {
                let a = self.key_off[idx as usize] as usize;
                let n = len as usize;
                if base[a..a + n] == base[off as usize..off as usize + n] {
                    return idx;
                }
            }
            idx = (idx + 1) & self.mask;
        }

        idx
    }

    fn claim(&mut self, idx: u64, off: u64, len: u64, value: u64) {
        let i = idx as usize;
        self.used[i] = 1;
        self.key_off[i] = off;
        self.key_len[i] = len;
        self.val[i] = value;
        self.count += 1;
    }
}

fn write_uint(buf: &mut [u8], pos: u64, v: u64) -> u64 {
    let mut tmp = [0u8; 24];
    let mut n: u64 = 0;
    let mut x = v;
    if x == 0 {
        tmp[0] = b'0';
        n = 1;
    }
    while x > 0 {
        tmp[n as usize] = (48 + (x % 10)) as u8;
        n += 1;
        x /= 10;
    }

    let mut p = pos;
    let mut i = n;
    while i > 0 {
        i -= 1;
        buf[p as usize] = tmp[i as usize];
        p += 1;
    }
    p
}

fn write_uint2(buf: &mut [u8], pos: u64, v: u64) -> u64 {
    buf[pos as usize] = (48 + (v / 10)) as u8;
    buf[(pos + 1) as usize] = (48 + (v % 10)) as u8;
    pos + 2
}

fn main() {
    // ---- data generation (not timed) ----
    let mut text = vec![0u8; (ROWS * 48) as usize];
    let mut n: u64 = 0;

    for j in 0..ROWS {
        if j > 0 {
            text[n as usize] = b'\n';
            n += 1;
        }

        let region = REGIONS[(rnd() % 8) as usize].as_bytes();
        let y = 2024 + (rnd() % 3);
        let m = 1 + (rnd() % 12);
        let d = 1 + (rnd() % 28);
        let qty = 1 + (rnd() % 50);
        let cents = 100 + (rnd() % 99900);

        n = write_uint(&mut text, n, j);
        text[n as usize] = b',';
        n += 1;
        for i in 0..region.len() {
            text[n as usize] = region[i];
            n += 1;
        }
        text[n as usize] = b',';
        n += 1;
        n = write_uint(&mut text, n, y);
        text[n as usize] = b'-';
        n += 1;
        n = write_uint2(&mut text, n, m);
        text[n as usize] = b'-';
        n += 1;
        n = write_uint2(&mut text, n, d);
        text[n as usize] = b',';
        n += 1;
        n = write_uint(&mut text, n, qty);
        text[n as usize] = b',';
        n += 1;
        n = write_uint(&mut text, n, cents / 100);
        text[n as usize] = b'.';
        n += 1;
        n = write_uint2(&mut text, n, cents % 100);
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut agg = ByteMap::new(64);

    let mut slot_count = vec![0u64; 64];
    let mut slot_qty = vec![0u64; 64];
    let mut slot_rev = vec![0.0f64; 64];
    let mut slot_max = vec![0.0f64; 64];

    let mut pos: u64 = 0;
    let mut rows: u64 = 0;

    while pos < n {
        let mut eol = pos;
        while eol < n && text[eol as usize] != b'\n' {
            eol += 1;
        }

        // field 0: id
        let mut p = pos;
        while p < eol && text[p as usize] != b',' {
            p += 1;
        }
        p += 1;

        // field 1: region
        let rs = p;
        while p < eol && text[p as usize] != b',' {
            p += 1;
        }
        let rlen = p - rs;
        p += 1;

        // field 2: date (skipped)
        while p < eol && text[p as usize] != b',' {
            p += 1;
        }
        p += 1;

        // field 3: qty
        let mut qty: u64 = 0;
        while p < eol && text[p as usize] != b',' {
            qty = qty * 10 + (text[p as usize] - 48) as u64;
            p += 1;
        }
        p += 1;

        // field 4: price
        let mut ip: u64 = 0;
        while p < eol && text[p as usize] != b'.' {
            ip = ip * 10 + (text[p as usize] - 48) as u64;
            p += 1;
        }
        p += 1;
        let mut fr: u64 = 0;
        while p < eol {
            fr = fr * 10 + (text[p as usize] - 48) as u64;
            p += 1;
        }
        let price = ip as f64 + fr as f64 / 100.0;

        let idx = agg.probe(&text, rs, rlen);
        if agg.used[idx as usize] == 0 {
            let slot = agg.count as usize;
            agg.claim(idx, rs, rlen, slot as u64);
            slot_count[slot] = 1;
            slot_qty[slot] = qty;
            slot_rev[slot] = qty as f64 * price;
            slot_max[slot] = price;
        } else {
            let slot = agg.val[idx as usize] as usize;
            slot_count[slot] += 1;
            slot_qty[slot] += qty;
            slot_rev[slot] += qty as f64 * price;
            if price > slot_max[slot] {
                slot_max[slot] = price;
            }
        }

        rows += 1;
        pos = eol + 1;
    }

    // sort the region keys, then fold them in order
    let mut order = [0u64; 64];
    let mut key_idx = [0u64; 64];
    let mut nk: u64 = 0;
    for i in 0..64usize {
        if agg.used[i] != 0 {
            key_idx[nk as usize] = i as u64;
            nk += 1;
        }
    }

    for i in 0..nk as usize {
        order[i] = i as u64;
    }
    for i in 0..nk as usize {
        let mut best = i;
        for j in 0..nk as usize {
            if j <= i {
                continue;
            }
            let a = key_idx[order[best] as usize] as usize;
            let b = key_idx[order[j] as usize] as usize;
            let mut la = agg.key_len[a];
            if agg.key_len[b] < la {
                la = agg.key_len[b];
            }
            let la = la as usize;
            let sb = &text[agg.key_off[b] as usize..agg.key_off[b] as usize + la];
            let sa = &text[agg.key_off[a] as usize..agg.key_off[a] as usize + la];
            match sb.cmp(sa) {
                std::cmp::Ordering::Less => best = j,
                std::cmp::Ordering::Equal => {
                    if agg.key_len[b] < agg.key_len[a] {
                        best = j;
                    }
                }
                std::cmp::Ordering::Greater => {}
            }
        }
        order.swap(i, best);
    }

    let mut check = rows;
    for k in 0..nk as usize {
        let slot = agg.val[key_idx[order[k] as usize] as usize] as usize;
        check += (k as u64 + 1) * ((slot_rev[slot] * 100.0 + 0.5) as u64 % 1000003);
        check += slot_count[slot] + slot_qty[slot] + (slot_max[slot] * 100.0 + 0.5) as u64;
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

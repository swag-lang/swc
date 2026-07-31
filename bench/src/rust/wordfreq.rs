// Same algorithm as the Swag / C++ versions: hand-rolled open-addressing map over
// byte-slice keys, then a quicksort on (count desc, key asc).
use std::time::Instant;

const VOCAB: u64 = 5000;
const WORDS: u64 = 2000000;
const CAP: u64 = 16384;

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

struct Sorter {
    text: Vec<u8>,
    cnt: Vec<u64>,
    off: Vec<u64>,
    len: Vec<u64>,
    idx: Vec<u64>,
}

impl Sorter {
    // count descending, then key bytes ascending
    fn less(&self, a: u64, b: u64) -> bool {
        let (a, b) = (a as usize, b as usize);
        if self.cnt[a] != self.cnt[b] {
            return self.cnt[a] > self.cnt[b];
        }

        let mut n = self.len[a];
        if self.len[b] < n {
            n = self.len[b];
        }
        let n = n as usize;
        let sa = &self.text[self.off[a] as usize..self.off[a] as usize + n];
        let sb = &self.text[self.off[b] as usize..self.off[b] as usize + n];
        match sa.cmp(sb) {
            std::cmp::Ordering::Less => true,
            std::cmp::Ordering::Greater => false,
            std::cmp::Ordering::Equal => self.len[a] < self.len[b],
        }
    }

    fn qsort(&mut self, low_in: i64, high_in: i64) {
        let mut low = low_in;
        let high = high_in;

        while low < high {
            let p = self.idx[((low + high) / 2) as usize];
            let mut i = low;
            let mut j = high;

            while i <= j {
                while self.less(self.idx[i as usize], p) {
                    i += 1;
                }
                while self.less(p, self.idx[j as usize]) {
                    j -= 1;
                }
                if i <= j {
                    self.idx.swap(i as usize, j as usize);
                    i += 1;
                    j -= 1;
                }
            }

            self.qsort(low, j);
            low = i;
        }
    }
}

fn main() {
    // ---- data generation (not timed) ----
    let mut vocab_bytes = vec![0u8; (VOCAB * 16) as usize];
    let mut vocab_off = vec![0u64; VOCAB as usize];
    let mut vocab_len = vec![0u64; VOCAB as usize];

    let mut vp: u64 = 0;
    for i in 0..VOCAB {
        let mut nn = i + 1;
        let l = 3 + (i % 6);
        vocab_off[i as usize] = vp;
        vocab_len[i as usize] = l;
        for k in 0..l {
            vocab_bytes[vp as usize] = (97 + (nn % 26)) as u8;
            vp += 1;
            nn = nn / 26 + 7 * k;
        }
    }

    let mut text = vec![0u8; (WORDS * 12) as usize];
    let mut n: u64 = 0;
    for j in 0..WORDS {
        let idx = rnd() % VOCAB;
        let o = vocab_off[idx as usize];
        let l = vocab_len[idx as usize];
        for k in 0..l {
            text[n as usize] = vocab_bytes[(o + k) as usize];
            n += 1;
        }
        text[n as usize] = if (j + 1) % 12 == 0 { b'\n' } else { b' ' };
        n += 1;
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut counts = ByteMap::new(CAP);

    let mut start: u64 = 0;
    let mut open = false;
    let mut i: u64 = 0;

    while i < n {
        let c = text[i as usize];
        if (97..=122).contains(&c) {
            if !open {
                start = i;
                open = true;
            }
        } else if open {
            let idx = counts.probe(&text, start, i - start);
            if counts.used[idx as usize] == 0 {
                counts.claim(idx, start, i - start, 1);
            } else {
                counts.val[idx as usize] += 1;
            }
            open = false;
        }
        i += 1;
    }

    if open {
        let idx = counts.probe(&text, start, n - start);
        if counts.used[idx as usize] == 0 {
            counts.claim(idx, start, n - start, 1);
        } else {
            counts.val[idx as usize] += 1;
        }
    }

    let distinct = counts.count;
    let mut s = Sorter {
        text,
        cnt: vec![0; distinct as usize],
        off: vec![0; distinct as usize],
        len: vec![0; distinct as usize],
        idx: vec![0; distinct as usize],
    };

    let mut ni: u64 = 0;
    for slot in 0..CAP as usize {
        if counts.used[slot] == 0 {
            continue;
        }
        s.cnt[ni as usize] = counts.val[slot];
        s.off[ni as usize] = counts.key_off[slot];
        s.len[ni as usize] = counts.key_len[slot];
        s.idx[ni as usize] = ni;
        ni += 1;
    }

    s.qsort(0, distinct as i64 - 1);

    let mut check = distinct * 7;
    for k in 0..20u64 {
        check += (k + 1) * s.cnt[s.idx[k as usize] as usize];
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

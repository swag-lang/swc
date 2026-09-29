use std::time::Instant;

const N: i64 = 300000;

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

fn qsort(a: &mut [u64], mut lo: i64, mut hi: i64) {
    while hi - lo > 16 {
        let mid = lo + (hi - lo) / 2;
        if a[mid as usize] < a[lo as usize] {
            a.swap(lo as usize, mid as usize);
        }
        if a[hi as usize] < a[lo as usize] {
            a.swap(lo as usize, hi as usize);
        }
        if a[hi as usize] < a[mid as usize] {
            a.swap(mid as usize, hi as usize);
        }

        let pivot = a[mid as usize];
        let mut i = lo;
        let mut j = hi;
        loop {
            while a[i as usize] < pivot {
                i += 1;
            }
            while a[j as usize] > pivot {
                j -= 1;
            }
            if i <= j {
                a.swap(i as usize, j as usize);
                i += 1;
                j -= 1;
            }
            if i > j {
                break;
            }
        }

        // Recurse into the smaller side, loop on the larger one.
        if j - lo < hi - i {
            qsort(a, lo, j);
            lo = i;
        } else {
            qsort(a, i, hi);
            hi = j;
        }
    }

    for i in lo + 1..=hi {
        let v = a[i as usize];
        let mut j = i - 1;
        while j >= lo && a[j as usize] > v {
            a[(j + 1) as usize] = a[j as usize];
            j -= 1;
        }
        a[(j + 1) as usize] = v;
    }
}

fn main() {
    // ---- data generation (not timed) ----
    let mut a = vec![0u64; N as usize];
    for i in 0..N as usize {
        a[i] = rnd();
    }

    // ---- timed work ----
    let start_t = Instant::now();

    qsort(&mut a, 0, N - 1);

    let mut sorted = true;
    for i in 1..N as usize {
        if a[i - 1] > a[i] {
            sorted = false;
        }
    }

    let mut check: u64 = 0;
    if sorted {
        for i in 0..N as usize {
            check += (a[i] % 1000) * (i as u64 % 7 + 1);
        }
    }

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

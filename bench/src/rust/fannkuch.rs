use std::time::Instant;

const N: usize = 9;

fn main() {
    // ---- data generation (not timed) ----
    let mut perm = vec![0i64; N];
    let mut perm1 = vec![0i64; N];
    let mut count = vec![0i64; N];

    // ---- timed work ----
    let start_t = Instant::now();

    for i in 0..N {
        perm1[i] = i as i64;
    }

    let mut checksum: i64 = 0;
    let mut max_flips: i64 = 0;
    let mut perm_count: i64 = 0;
    let mut r = N;

    loop {
        while r != 1 {
            count[r - 1] = r as i64;
            r -= 1;
        }

        for i in 0..N {
            perm[i] = perm1[i];
        }

        let mut flips: i64 = 0;
        let mut k = perm[0] as usize;
        while k != 0 {
            let mut i = 0usize;
            let mut j = k;
            while i < j {
                perm.swap(i, j);
                i += 1;
                j -= 1;
            }
            flips += 1;
            k = perm[0] as usize;
        }

        if flips > max_flips {
            max_flips = flips;
        }
        if perm_count % 2 == 0 {
            checksum += flips;
        } else {
            checksum -= flips;
        }

        // Rotate the prefix to reach the next permutation.
        let mut done = false;
        loop {
            if r == N {
                done = true;
                break;
            }
            let perm0 = perm1[0];
            for i in 0..r {
                perm1[i] = perm1[i + 1];
            }
            perm1[r] = perm0;
            count[r] -= 1;
            if count[r] > 0 {
                break;
            }
            r += 1;
        }
        if done {
            break;
        }
        perm_count += 1;
    }

    let check = (checksum * 1000 + max_flips) as u64;

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

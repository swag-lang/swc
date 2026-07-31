use std::time::Instant;

const N: u64 = 800;
const NN: u64 = N * N;
const INF: u64 = 0x0FFFFFFFFFFFFFFF;

static mut G_SEED: u64 = 12345;

fn rnd() -> u64 {
    unsafe {
        G_SEED = (G_SEED * 16807) % 2147483647;
        G_SEED
    }
}

struct Heap {
    d: Vec<u64>,
    n: Vec<u64>,
    size: u64,
}

impl Heap {
    fn push(&mut self, d: u64, node: u64) {
        let mut i = self.size;
        self.size += 1;
        self.d[i as usize] = d;
        self.n[i as usize] = node;

        while i > 0 {
            let p = (i - 1) >> 1;
            if self.d[p as usize] <= self.d[i as usize] {
                break;
            }
            self.d.swap(p as usize, i as usize);
            self.n.swap(p as usize, i as usize);
            i = p;
        }
    }

    fn pop(&mut self) -> (u64, u64) {
        let pop_d = self.d[0];
        let pop_n = self.n[0];
        self.size -= 1;
        self.d[0] = self.d[self.size as usize];
        self.n[0] = self.n[self.size as usize];

        let mut i = 0u64;
        loop {
            let l = 2 * i + 1;
            if l >= self.size {
                break;
            }
            let r = l + 1;
            let mut m = l;
            if r < self.size && self.d[r as usize] < self.d[l as usize] {
                m = r;
            }
            if self.d[i as usize] <= self.d[m as usize] {
                break;
            }
            self.d.swap(m as usize, i as usize);
            self.n.swap(m as usize, i as usize);
            i = m;
        }

        (pop_d, pop_n)
    }
}

fn main() {
    // ---- data generation (not timed) ----
    let mut weight = vec![0u64; NN as usize];
    for i in 0..NN as usize {
        weight[i] = 1 + (rnd() % 9);
    }

    // ---- timed work ----
    let start_t = Instant::now();

    let mut dist = vec![INF; NN as usize];

    let mut heap = Heap {
        d: vec![0; (NN * 4) as usize],
        n: vec![0; (NN * 4) as usize],
        size: 0,
    };

    dist[0] = 0;
    heap.push(0, 0);

    let mut pops: u64 = 0;
    let target = NN - 1;

    while heap.size > 0 {
        let (d, u) = heap.pop();
        pops += 1;
        if d > dist[u as usize] {
            continue;
        }
        if u == target {
            break;
        }

        let x = u % N;
        let y = u / N;

        if x > 0 {
            let v = u - 1;
            let nd = d + weight[v as usize];
            if nd < dist[v as usize] {
                dist[v as usize] = nd;
                heap.push(nd, v);
            }
        }
        if x < N - 1 {
            let v = u + 1;
            let nd = d + weight[v as usize];
            if nd < dist[v as usize] {
                dist[v as usize] = nd;
                heap.push(nd, v);
            }
        }
        if y > 0 {
            let v = u - N;
            let nd = d + weight[v as usize];
            if nd < dist[v as usize] {
                dist[v as usize] = nd;
                heap.push(nd, v);
            }
        }
        if y < N - 1 {
            let v = u + N;
            let nd = d + weight[v as usize];
            if nd < dist[v as usize] {
                dist[v as usize] = nd;
                heap.push(nd, v);
            }
        }
    }

    let check = dist[target as usize] * 1000 + (pops % 1000);

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", check, ms);
}

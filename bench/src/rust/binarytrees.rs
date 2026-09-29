use std::time::Instant;

const MIN_DEPTH: u32 = 4;
const MAX_DEPTH: u32 = 12;

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

fn bottom_up(depth: u32) -> Box<Node> {
    if depth > 0 {
        Box::new(Node {
            left: Some(bottom_up(depth - 1)),
            right: Some(bottom_up(depth - 1)),
        })
    } else {
        Box::new(Node { left: None, right: None })
    }
}

fn check(node: &Node) -> u64 {
    match (&node.left, &node.right) {
        (Some(l), Some(r)) => 1 + check(l) + check(r),
        _ => 1,
    }
}

fn main() {
    // ---- timed work (no input data) ----
    let start_t = Instant::now();

    let mut total: u64 = 0;

    let stretch = bottom_up(MAX_DEPTH + 1);
    total += check(&stretch);
    drop(stretch);

    let long_lived = bottom_up(MAX_DEPTH);

    let mut d = MIN_DEPTH;
    while d <= MAX_DEPTH {
        let iterations = 1u64 << (MAX_DEPTH - d + MIN_DEPTH);
        for _ in 0..iterations {
            let tree = bottom_up(d);
            total += check(&tree);
            drop(tree);
        }
        d += 2;
    }

    total += check(&long_lived);
    drop(long_lived);

    let ms = start_t.elapsed().as_secs_f64() * 1000.0;
    println!("CHECK={} MS={:.6}", total, ms);
}

import WinSDK
import Foundation

let MIN_DEPTH = 4
let MAX_DEPTH = 12

func now() -> Double {
    var c = LARGE_INTEGER()
    var f = LARGE_INTEGER()
    QueryPerformanceCounter(&c)
    QueryPerformanceFrequency(&f)
    return Double(c.QuadPart) / Double(f.QuadPart)
}

final class Node {
    let left: Node?
    let right: Node?

    init(_ left: Node?, _ right: Node?) {
        self.left = left
        self.right = right
    }
}

func bottomUp(_ depth: Int) -> Node {
    if depth > 0 {
        return Node(bottomUp(depth - 1), bottomUp(depth - 1))
    }
    return Node(nil, nil)
}

func check(_ node: Node) -> UInt64 {
    if let left = node.left, let right = node.right {
        return 1 &+ check(left) &+ check(right)
    }
    return 1
}

func runMain() {
    // ---- timed work (no input data) ----
    let t0 = now()

    var total: UInt64 = 0

    do {
        let stretch = bottomUp(MAX_DEPTH + 1)
        total &+= check(stretch)
    }

    var longLived: Node? = bottomUp(MAX_DEPTH)

    var d = MIN_DEPTH
    while d <= MAX_DEPTH {
        let iterations = 1 << (MAX_DEPTH - d + MIN_DEPTH)
        for _ in 0..<iterations {
            let tree = bottomUp(d)
            total &+= check(tree)
        }
        d += 2
    }

    total &+= check(longLived!)
    longLived = nil

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", total, (t1 - t0) * 1000.0))
}

runMain()

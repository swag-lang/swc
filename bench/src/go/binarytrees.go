package main

import "time"

type node struct{ left, right *node }

func bottomUp(depth int) *node {
	if depth > 0 {
		return &node{bottomUp(depth - 1), bottomUp(depth - 1)}
	}
	return &node{}
}

func checkTree(n *node) int {
	if n.left == nil {
		return 1
	}
	return 1 + checkTree(n.left) + checkTree(n.right)
}

func main() {
	const minDepth, maxDepth = 4, 12
	start := time.Now()
	stretch := bottomUp(maxDepth + 1)
	total := checkTree(stretch)
	stretch = nil
	longLived := bottomUp(maxDepth)
	for d := minDepth; d <= maxDepth; d += 2 {
		iterations := 1 << (maxDepth - d + minDepth)
		for i := 0; i < iterations; i++ {
			total += checkTree(bottomUp(d))
		}
	}
	total += checkTree(longLived)
	report(total, start)
}

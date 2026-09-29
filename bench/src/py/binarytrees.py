import sys
import time

MIN_DEPTH = 4
MAX_DEPTH = 12

sys.setrecursionlimit(10000)

class Node:
    __slots__ = ("left", "right")

    def __init__(self, left, right):
        self.left = left
        self.right = right

def bottom_up(depth):
    if depth > 0:
        return Node(bottom_up(depth - 1), bottom_up(depth - 1))
    return Node(None, None)

def check(node):
    if node.left is None:
        return 1
    return 1 + check(node.left) + check(node.right)

# ---- timed work (no input data) ----
t0 = time.perf_counter()

total = 0

stretch = bottom_up(MAX_DEPTH + 1)
total += check(stretch)
stretch = None

long_lived = bottom_up(MAX_DEPTH)

for d in range(MIN_DEPTH, MAX_DEPTH + 1, 2):
    iterations = 1 << (MAX_DEPTH - d + MIN_DEPTH)
    for i in range(iterations):
        tree = bottom_up(d)
        total += check(tree)
        tree = None

total += check(long_lived)
long_lived = None

t1 = time.perf_counter()
print("CHECK=%d MS=%.3f" % (total, (t1 - t0) * 1000.0))

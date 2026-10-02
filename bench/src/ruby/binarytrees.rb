MIN_DEPTH = 4
MAX_DEPTH = 12
class Node
  attr_accessor :left, :right

  def initialize(left, right)
    @left = left
    @right = right
  end

end

def bottom_up(depth)
  if (depth > 0)
    return Node.new(bottom_up((depth - 1)), bottom_up((depth - 1)))
  end
  return Node.new(nil, nil)
end

def check(node)
  if (node.left == nil)
    return 1
  end
  return ((1 + check(node.left)) + check(node.right))
end

# Timed work; input generation above is excluded.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
total = 0
stretch = bottom_up((MAX_DEPTH + 1))
total += check(stretch)
stretch = nil
long_lived = bottom_up(MAX_DEPTH)
(MIN_DEPTH).step(((MAX_DEPTH + 1)) - 1, 2) do |d|
  iterations = (1 << ((MAX_DEPTH - d) + MIN_DEPTH))
  (0).step((iterations) - 1, 1) do |i|
    tree = bottom_up(d)
    total += check(tree)
    tree = nil
  end
end
total += check(long_lived)
long_lived = nil
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("CHECK=%d MS=%.3f", total, ((t1 - t0) * 1000.0))

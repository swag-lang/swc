final class Node
{
    public Node left;
    public Node right;

    public Node(Node left, Node right)
    {
        this.left = left;
        this.right = right;
    }
}

class Bench
{
    static final int MIN_DEPTH = 4;
    static final int MAX_DEPTH = 12;

    static Node bottomUp(int depth)
    {
        if (depth > 0)
            return new Node(bottomUp(depth - 1), bottomUp(depth - 1));
        return new Node(null, null);
    }

    static long check(Node node)
    {
        if (node.left == null)
            return 1;
        return 1 + check(node.left) + check(node.right);
    }

    public static void main(String[] args)
    {
        // ---- timed work (no input data) ----
        long startTime = System.nanoTime();

        long total = 0;

        Node stretch = bottomUp(MAX_DEPTH + 1);
        total += check(stretch);
        stretch = null;

        Node longLived = bottomUp(MAX_DEPTH);

        for (int d = MIN_DEPTH; d <= MAX_DEPTH; d += 2)
        {
            long iterations = 1L << (MAX_DEPTH - d + MIN_DEPTH);
            for (long i = 0; i < iterations; i++)
            {
                Node tree = bottomUp(d);
                total += check(tree);
            }
        }

        total += check(longLived);
        longLived = null;

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", total, ms);
        return;
    }
}

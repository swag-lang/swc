using System;
using System.Diagnostics;

sealed class Node
{
    public Node Left;
    public Node Right;

    public Node(Node left, Node right)
    {
        Left = left;
        Right = right;
    }
}

static class Bench
{
    const int MIN_DEPTH = 4;
    const int MAX_DEPTH = 12;

    static Node BottomUp(int depth)
    {
        if (depth > 0)
            return new Node(BottomUp(depth - 1), BottomUp(depth - 1));
        return new Node(null, null);
    }

    static ulong Check(Node node)
    {
        if (node.Left == null)
            return 1;
        return 1 + Check(node.Left) + Check(node.Right);
    }

    static int Main()
    {
        // ---- timed work (no input data) ----
        long start_t = Stopwatch.GetTimestamp();

        ulong total = 0;

        Node stretch = BottomUp(MAX_DEPTH + 1);
        total += Check(stretch);
        stretch = null;

        Node longLived = BottomUp(MAX_DEPTH);

        for (int d = MIN_DEPTH; d <= MAX_DEPTH; d += 2)
        {
            ulong iterations = 1UL << (MAX_DEPTH - d + MIN_DEPTH);
            for (ulong i = 0; i < iterations; i++)
            {
                Node tree = BottomUp(d);
                total += Check(tree);
            }
        }

        total += Check(longLived);
        longLived = null;

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={total} MS={ms:F6}");
        return 0;
    }
}

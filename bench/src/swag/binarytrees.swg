const MIN_DEPTH = 4's32
const MAX_DEPTH = 12's32

struct Node
{
    left:  *Node?
    right: *Node?
}

func bottomUp(depth: s32)->*Node
{
    let node = cast(*Node) (benchAlloc(#sizeof(Node)))!
    if depth > 0
    {
        node.left  = bottomUp(depth - 1)
        node.right = bottomUp(depth - 1)
    }
    else
    {
        node.left  = null
        node.right = null
    }

    return node
}

func check(node: *Node)->u64
{
    if node.left and node.right do
        return 1 + check(node.left) + check(node.right)
    return 1
}

func release(node: *Node)
{
    if node.left and node.right
    {
        release(node.left)
        release(node.right)
    }

    benchFree(node)
}

#run
{
    // ---- timed work (no input data) ----
    let t0 = now()

    var total = 0'u64

    let stretch = bottomUp(MAX_DEPTH + 1)
    total += check(stretch)
    release(stretch)

    let longLived = bottomUp(MAX_DEPTH)

    var d = MIN_DEPTH
    while d <= MAX_DEPTH
    {
        let iterations = 1'u64 << cast(u64) (MAX_DEPTH - d + MIN_DEPTH)
        for iterations
        {
            let tree = bottomUp(d)
            total += check(tree)
            release(tree)
        }

        d += 2
    }

    total += check(longLived)
    release(longLived)

    let t1 = now()
    report(total, t0, t1)
}

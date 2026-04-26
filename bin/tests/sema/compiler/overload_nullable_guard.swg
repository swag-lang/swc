#global fileprivate

struct Node
{
}

func pick()->bool
{
    var n: *Node = null
    return pick(n)
}

func pick(n: *Node)->bool
{
    return n != null
}

func select(n: #null *Node)->bool
{
    if !n do
        return false
    return select(n)
}

func select(n: *Node)->bool
{
    return n != null
}

#test
{
    var node: Node
    @assert(!pick())
    @assert(select(&node))
}

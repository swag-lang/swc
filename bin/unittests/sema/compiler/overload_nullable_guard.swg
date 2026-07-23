#global private

struct Node {}

struct GuardedNode {}

impl GuardedNode
{
    mtd check()->bool
    {
        return true
    }
}

func pick()->bool
{
    var n: #null *Node = null
    return pick(n)
}

func pick(n: #null *Node)->bool
{
    return n != null
}

func select(n: #null *Node)->bool
{
    if !n do
        return false
    return select(notnull n)
}

func select(n: *Node)->bool
{
    return n != null
}

func guardedMethod(n: #null *GuardedNode)->bool
{
    if n do
        return n.check()
    return false
}

func guardedAssume(n: #null *GuardedNode)->bool
{
    if n
    {
        let checked = notnull n
        return checked.check()
    }
    return false
}

func semaTest001()
{
    var node:        Node
    var guardedNode: GuardedNode
    @assert(!pick())
    @assert(select(&node))
    @assert(guardedMethod(&guardedNode))
    @assert(guardedAssume(&guardedNode))
}

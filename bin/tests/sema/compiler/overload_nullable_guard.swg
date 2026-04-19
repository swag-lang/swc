#global fileprivate

struct Node
{
}

#[Swag.Overload]
func pick()->bool
{
    var n: *Node = null
    return pick(n)
}

#[Swag.Overload]
func pick(n: *Node)->bool
{
    return n != null
}

#[Swag.Overload]
func select(n: #null *Node)->bool
{
    if !n do
        return false
    return select(n)
}

#[Swag.Overload]
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

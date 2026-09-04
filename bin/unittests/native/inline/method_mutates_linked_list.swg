#global private

struct InlineBug11Node
{
    value: u32
    next:  *InlineBug11Node?
    prev:  *InlineBug11Node?
}

struct InlineBug11List
{
    head: *InlineBug11Node?
}

impl InlineBug11List
{
    #[Swag.Inline]
    mtd unlink(node: *InlineBug11Node)
    {
        let next = node.next
        let prev = node.prev

        if prev do
            prev.next = next
        else do
            .head = next

        if next do
            next.prev = prev

        node.next, node.prev = null
    }

    mtd pop(outNode: **InlineBug11Node)->bool
    {
        let head = .head
        if !head do
            return false

        let node = head!
        outNode[] = node
        .unlink(node)
        return true
    }
}

#test
{
    var nodes: [2] InlineBug11Node
    nodes[0].value = 10
    nodes[1].value = 20
    nodes[0].next  = &nodes[1]
    nodes[1].prev  = &nodes[0]

    var list = InlineBug11List{&nodes[0]}
    var popped: *InlineBug11Node? = null
    Swag.assert(list.pop(&popped))
    Swag.assert(popped! == &nodes[0])
    Swag.assert(list.head == &nodes[1])
    Swag.assert(nodes[0].next == null)
    Swag.assert(nodes[0].prev == null)
    Swag.assert(nodes[1].prev == null)
}

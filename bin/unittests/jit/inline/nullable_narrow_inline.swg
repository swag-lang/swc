#global private

struct Node
{
    value: s32
    next:  *Node?
}

var storage: Node

#[Swag.NoInline]
func opaqueNode(node: *Node?)->*Node? => node

#[Swag.Inline]
func narrowedByTest(node: *Node?)->s32
{
    if node == null do
        return -1
    return node.value
}

#[Swag.Inline]
func narrowedIndex(values: [..] s32?)->s32
{
    if values == null do
        return -1
    return values[0]
}

alias Compute = func(s32)->s32

#[Swag.NoInline]
func doubleIt(value: s32)->s32 => value * 2

#[Swag.Inline]
func narrowedCall(compute: Compute?, value: s32)->s32
{
    if compute == null do
        return -1
    return compute(value)
}

#test
{
    storage.value = 5
    var values = [1, 2, 3]
    Swag.require(narrowedIndex(values) == 1)
    Swag.require(narrowedIndex(null) == -1)
    Swag.require(narrowedCall(&doubleIt, 4) == 8)
    Swag.require(narrowedCall(null, 4) == -1)
    Swag.require(narrowedByTest(&storage) == 5)
    Swag.require(narrowedByTest(opaqueNode(null)) == -1)
}

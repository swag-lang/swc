#global private

struct UnwrapNode { value: s32 }

var g_unwrapNode = UnwrapNode{42}
var g_unwrapCalls: s32

func unwrapNode(present: bool)->*UnwrapNode?
{
    g_unwrapCalls += 1
    return present ? &g_unwrapNode : null
}

func unwrapFallible(present: bool)->*UnwrapNode? fail => present ? &g_unwrapNode : null

func unwrapNullable(node: *UnwrapNode?)->*UnwrapNode => unwrap node

#test
{
    g_unwrapCalls = 0
    let node = unwrap unwrapNode(true)
    #assert(#typeof(node) == *UnwrapNode)
    Swag.assert(node.value == 42)
    Swag.assert(g_unwrapCalls == 1)
}

#test
{
    alias Slot = *UnwrapNode?
    var values: [2] Slot = [null, &g_unwrapNode]
    let node = unwrap values[1]
    #assert(#typeof(node) == *UnwrapNode)
    Swag.assert(node.value == 42)
    Swag.assert(unwrapNullable(&g_unwrapNode).value == 42)
}

#test
{
    let node = unwrap expect unwrapFallible(true)
    #assert(#typeof(node) == *UnwrapNode)
    Swag.assert(node.value == 42)
}

func unwrapProof(node: *UnwrapNode?)->s32
{
    let present = unwrap node
    return present.value + node.value
}

#test
{
    Swag.assert(unwrapProof(&g_unwrapNode) == 84)
    g_unwrapCalls = 0
    let node = true ? &g_unwrapNode : unwrap unwrapNode(true)
    Swag.assert(node.value == 42)
    Swag.assert(g_unwrapCalls == 0)
}

enum UnwrapKind { Empty, Node }

struct UnwrapUnion
{
    using payload: union(UnwrapKind)
    {
        case .Node: node: UnwrapNode
    } = .Empty
}

func unwrapPayload(value: UnwrapUnion)->s32
{
    let node = unwrap value.node
    return node.value
}

#test
{
    var value: UnwrapUnion
    value.payload = .Node{UnwrapNode{42}}
    Swag.assert(unwrapPayload(value) == 42)
}

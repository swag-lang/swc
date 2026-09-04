#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    // Directory traversal is independent of the volume-wide node count. The
    // linked child index must retain insertion order while supporting constant-
    // time continuation from every emitted node.
    const NodeCount = 100_000'u64

    var nodes: Array'Node
    nodes.reserve(NodeCount + 1)

    var root: Node
    root.id       = RootNodeId
    root.parentId = RootNodeId
    nodes.add(#move root)

    var index: NodeIndex
    Swag.assert(index.add(&nodes[0], 0))
    for i in NodeCount
    {
        var node: Node
        node.id       = i + RootNodeId + 1
        node.parentId = RootNodeId
        node.name     = Format.toString("entry_%", i)
        let position = nodes.count
        nodes.add(#move node)
        Swag.assert(index.add(&nodes[position], position))
    }

    Swag.assert(index.childId(RootNodeId, "ENTRY_99999") == NodeCount + RootNodeId)

    var childId = index.firstChildId(RootNodeId)
    var count   = 0'u64
    while childId
    {
        Swag.assert(childId == count + RootNodeId + 1)
        childId = index.nextSiblingId(childId)
        count   += 1
    }

    Swag.assert(count == NodeCount)

    // Removing alternating children exercises both ends and every interior
    // link without turning removal into an ordered-array shift.
    var i = 0'u64
    while i < NodeCount
    {
        index.remove(&nodes[i + 1])
        i += 2
    }

    childId = index.firstChildId(RootNodeId)
    count   = 0
    while childId
    {
        Swag.assert(childId == count * 2 + RootNodeId + 2)
        childId = index.nextSiblingId(childId)
        count   += 1
    }

    Swag.assert(count == NodeCount / 2 and index.hasChildren(RootNodeId))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    var nodes: Array'Node
    nodes.reserve(4)

    var root: Node
    root.id       = RootNodeId
    root.parentId = RootNodeId
    nodes.add(#move root)

    var index: NodeIndex
    let rootAdded = index.add(&nodes[0], 0)
    Swag.require(rootAdded)

    let rootRenamed = index.changeParent(&nodes[0], RootNodeId, "renamed-root")
    Swag.require(rootRenamed)
    Swag.require(index.childId(RootNodeId, "renamed-root") == Swag.U64.Max)

    for i in 3
    {
        var node: Node
        node.id       = i + RootNodeId + 1
        node.parentId = RootNodeId
        node.name     = Format.toString("entry_%", i)
        let position = nodes.count
        nodes.add(#move node)
        let nodeAdded = index.add(&nodes[position], position)
        Swag.require(nodeAdded)
    }

    let childRenamed = index.changeParent(&nodes[2], RootNodeId, "renamed_entry_1")
    Swag.require(childRenamed)
    Swag.require(index.childId(RootNodeId, "entry_1") == Swag.U64.Max)
    Swag.require(index.childId(RootNodeId, "RENAMED_ENTRY_1") == RootNodeId + 2)

    Swag.require(index.firstChildId(RootNodeId) == RootNodeId + 1)
    Swag.require(index.nextSiblingId(RootNodeId + 1) == RootNodeId + 2)
    Swag.require(index.nextSiblingId(RootNodeId + 2) == RootNodeId + 3)
    Swag.require(index.nextSiblingId(RootNodeId + 3) == 0)
}

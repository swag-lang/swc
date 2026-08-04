using Core

func childIndexKey(parentId: u64, name: string)->String
{
    var folded = String.from(name)
    folded.makeLower(.Unicode)
    return Format.toString("%:%", parentId, folded)
}

struct NodeIndex
{
    byId:        HashTable'(u64, u64)
    byParent:    HashTable'(String, u64)
    childCounts: HashTable'(u64, u64)
}

impl NodeIndex
{
    mtd add(node: *Node, index: u64)->bool
    {
        if .byId.contains(node.id) do
            return false
        if node.id != RootNodeId
        {
            let key = childIndexKey(node.parentId, node.name.toString())
            if .byParent.contains(key) do
                return false
            .byParent.add(#move key, node.id)
            let count = .childCounts.findOrAdd(node.parentId)
            count.value += 1
        }

        .byId.add(node.id, index)
        return true
    }

    mtd remove(node: *Node)
    {
        .byId.remove(node.id)
        if node.id == RootNodeId do
            return

        .byParent.remove(childIndexKey(node.parentId, node.name.toString()))
        let count = .childCounts.tryFind(node.parentId)
        if !count do
            return
        Debug.assert(count!.value != 0)
        count.value -= 1
        if !count.value do
            .childCounts.remove(node.parentId)
    }

    mtd updateNodePosition(nodeId, index: u64)
    {
        let entry = .byId.tryFind(nodeId)
        Debug.assert(entry != null)
        entry!.value = index
    }

    mtd nodePosition(id: u64)->u64
    {
        let entry = .byId.tryFind(id)
        return entry ? entry!.value : Swag.U64.Max
    }

    mtd childId(parentId: u64, name: string)->u64
    {
        let entry = .byParent.tryFind(childIndexKey(parentId, name))
        return entry ? entry!.value : Swag.U64.Max
    }

    mtd hasChildren(id: u64)->bool
    {
        let entry = .childCounts.tryFind(id)
        return entry != null and entry!.value != 0
    }

    mtd changeParent(node: *Node, parentId: u64, name: string)->bool
    {
        let key         = childIndexKey(parentId, name)
        let destination = .byParent.tryFind(key)
        if destination != null and destination!.value != node.id do
            return false

        if node.parentId != parentId or node.name.toString() != name
        {
            let position = .nodePosition(node.id)
            Debug.assert(position != Swag.U64.Max)
            .remove(node)
            node.parentId = parentId
            node.name     = name
            let added = .add(node, position)
            Debug.assert(added)
        }

        return true
    }
}

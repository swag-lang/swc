using Core

func childIndexKey(parentId: u64, name: string)->String
{
    var folded = String.from(name)
    folded.makeLower(.Unicode)
    return Format.toString("%:%", parentId, folded)
}

struct NodeIndexChildList
{
    firstId: u64
    lastId:  u64
}

struct NodeIndexSiblingLinks
{
    previousId: u64
    nextId:     u64
}

struct NodeIndex
{
    byId:       HashTable'(u64, u64)
    byParent:   HashTable'(String, u64)
    childLists: HashTable'(u64, NodeIndexChildList)
    siblings:   HashTable'(u64, NodeIndexSiblingLinks)
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

            let children = .childLists.findOrAdd(node.parentId)
            var links: NodeIndexSiblingLinks
            links.previousId = children.value.lastId
            if children.value.lastId
            {
                let previous = .siblings.tryFind(children.value.lastId)
                Debug.assert(previous != null)
                previous!.value.nextId = node.id
            }
            else do
                children.value.firstId = node.id
            children.value.lastId = node.id
            .siblings.add(node.id, links)
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
        let links    = .siblings.tryFind(node.id)
        let children = .childLists.tryFind(node.parentId)
        Debug.assert(links != null and children != null)

        let previousId = links!.value.previousId
        let nextId     = links!.value.nextId
        if previousId
        {
            let previous = .siblings.tryFind(previousId)
            Debug.assert(previous != null)
            previous!.value.nextId = nextId
        }
        else do
            children!.value.firstId = nextId

        if nextId
        {
            let next = .siblings.tryFind(nextId)
            Debug.assert(next != null)
            next!.value.previousId = previousId
        }
        else do
            children!.value.lastId = previousId

        .siblings.remove(node.id)
        if !children!.value.firstId do
            .childLists.remove(node.parentId)
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
        return .firstChildId(id) != 0
    }

    mtd firstChildId(parentId: u64)->u64
    {
        let entry = .childLists.tryFind(parentId)
        return entry ? entry!.value.firstId : 0
    }

    mtd nextSiblingId(id: u64)->u64
    {
        let entry = .siblings.tryFind(id)
        return entry ? entry!.value.nextId : 0
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

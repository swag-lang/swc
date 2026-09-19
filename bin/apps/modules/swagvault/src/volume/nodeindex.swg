using Core

// First and last child of one directory, in insertion order.
struct NodeIndexChildList
{
    firstId: u64
    lastId:  u64
}

// Neighbours of one node among the children of its directory; zero means none.
struct NodeIndexSiblingLinks
{
    previousId: u64
    nextId:     u64
}

// Finds a node by identifier, by name inside its directory, and by walking a directory's children.
//
// Names are matched without case, as Windows matches them. Children are linked in insertion
// order, so listing a directory never depends on how many nodes the volume holds.
struct NodeIndex
{
    byId:       HashTable'(u64, u64)                       // Position of each node in the node table.
    byParent:   HashTable'(String, u64)                    // Node of each case-folded name, per directory.
    childLists: HashTable'(u64, NodeIndexChildList)        // Children of each non-empty directory.
    siblings:   HashTable'(u64, NodeIndexSiblingLinks)     // Neighbours of each node except the root.
}

impl NodeIndex
{
    // Returns the `byParent` key of `name` inside the directory `parentId`.
    func childKey(parentId: u64, name: string)->String
    {
        var folded = String.from(name)
        folded.makeLower(.Unicode)
        return Format.toString("%:%", parentId, folded)
    }

    // Indexes `node` at position `index` of the node table.
    //
    // Returns false, and changes nothing, when the identifier is already indexed or the name is
    // already taken in its directory.
    mtd add(node: *Node, index: u64)->bool
    {
        if .byId.contains(node.id) do
            return false
        if node.id != RootNodeId
        {
            let key = childKey(node.parentId, node.name.toString())
            if .byParent.contains(key) do
                return false
            .byParent.add(#move key, node.id)

            let children = .childLists.findOrAdd(node.parentId)
            var links: NodeIndexSiblingLinks
            links.previousId = children.value.lastId
            if children.value.lastId
            {
                let previous = .siblings.tryFind(children.value.lastId)
                Swag.assert(previous != null)
                previous.value.nextId = node.id
            }
            else do
                children.value.firstId = node.id
            children.value.lastId = node.id
            .siblings.add(node.id, links)
        }

        .byId.add(node.id, index)
        return true
    }

    // Removes `node` from every index, relinking its neighbours.
    mtd remove(node: *Node)
    {
        .byId.remove(node.id)
        if node.id == RootNodeId do
            return

        .byParent.remove(childKey(node.parentId, node.name.toString()))
        let links    = .siblings.tryFind(node.id)
        let children = .childLists.tryFind(node.parentId)
        Swag.assert(links != null and children != null)

        let previousId = links.value.previousId
        let nextId     = links.value.nextId
        if previousId
        {
            let previous = .siblings.tryFind(previousId)
            Swag.assert(previous != null)
            previous.value.nextId = nextId
        }
        else do
            children.value.firstId = nextId

        if nextId
        {
            let next = .siblings.tryFind(nextId)
            Swag.assert(next != null)
            next.value.previousId = previousId
        }
        else do
            children.value.lastId = previousId

        .siblings.remove(node.id)
        if not children.value.firstId do
            .childLists.remove(node.parentId)
    }

    // Records that the node `nodeId` moved to position `index` of the node table.
    mtd updateNodePosition(nodeId, index: u64)
    {
        let entry = .byId.tryFind(nodeId)
        Swag.assert(entry != null)
        entry.value = index
    }

    // Returns the position of the node `id` in the node table, or `Swag.U64.Max` when it is not indexed.
    mtd nodePosition(id: u64)->u64
    {
        let entry = .byId.tryFind(id)
        return entry ? entry.value : Swag.U64.Max
    }

    // Returns the node called `name` in the directory `parentId`, or `Swag.U64.Max` when there is none.
    mtd childId(parentId: u64, name: string)->u64
    {
        let entry = .byParent.tryFind(childKey(parentId, name))
        return entry ? entry.value : Swag.U64.Max
    }

    mtd hasChildren(id: u64)->bool => .firstChildId(id) != 0

    // Returns the first child of the directory `parentId`, or zero when it is empty.
    mtd firstChildId(parentId: u64)->u64
    {
        let entry = .childLists.tryFind(parentId)
        return entry ? entry.value.firstId : 0
    }

    // Returns the child that follows `id` in its directory, or zero when it is the last.
    mtd nextSiblingId(id: u64)->u64
    {
        let entry = .siblings.tryFind(id)
        return entry ? entry.value.nextId : 0
    }

    // Moves `node` under `parentId` as `name`, updating the node itself.
    //
    // Returns false, and changes nothing, when another node already has that name there.
    mtd changeParent(node: *Node, parentId: u64, name: string)->bool
    {
        let key         = childKey(parentId, name)
        let destination = .byParent.tryFind(key)
        if destination != null and destination.value != node.id do
            return false

        if node.parentId != parentId or node.name.toString() != name
        {
            let position = .nodePosition(node.id)
            Swag.assert(position != Swag.U64.Max)
            .remove(node)
            node.parentId = parentId
            node.name     = name
            let added = .add(node, position)
            Swag.assert(added)
        }

        return true
    }
}

// Splits a path into its names, on either separator.
//
// Windows never allows '/' inside a name, so a '/' that reaches the volume can only be a
// separator a caller left unconverted: a verbatim `\\?\` path skips the conversion Win32 applies
// to every other path. Keeping it inside a name would store an entry Windows can neither list
// under its directory nor open, which is how a container came to hold hundreds of unreachable
// files under names such as `vid/clip.mp4`.
private func splitPath(path: string)->Array'string
{
    var result: retval
    let bytes = cast(const [..] u8, path)
    var start = 0'u64
    for i in bytes.count + 1
    {
        if i < bytes.count and bytes[i] != cast(u8, '\\') and bytes[i] != cast(u8, '/') do
            continue
        if i > start
        {
            let name: string = cast(Swag.makeSlice(bytes.buffer + start, i - start))
            result.add(name)
        }

        start = i + 1
    }

    return result
}

impl Volume
{
    // Navigation through the node lookup; each returns null when there is no such node.
    mtd nodeById(id: u64)->*Node?
    {
        let index = .nodeLookup.nodePosition(id)
        return index != Swag.U64.Max ? &.nodes[index] : null
    }

    mtd findChild(parentId: u64, name: string)->*Node?
    {
        let id = .nodeLookup.childId(parentId, name)
        return id != Swag.U64.Max ? .nodeById(id) : null
    }

    mtd firstChild(parentId: u64)->*Node?
    {
        let id = .nodeLookup.firstChildId(parentId)
        return id ? .nodeById(id) : null
    }

    mtd nextSibling(id: u64)->*Node?
    {
        let nextId = .nodeLookup.nextSiblingId(id)
        return nextId ? .nodeById(nextId) : null
    }

    mtd resolve(path: string)->*Node?
    {
        let parts   = splitPath(path)
        var current = .nodeById(RootNodeId)
        if not current do
            return null
        for part in parts
        {
            current = .findChild(current.id, part)
            if not current do
                return null
        }

        return current
    }

    // The directory that holds `path`, and the last name of the path; a null parent when a
    // directory on the way is missing.
    mtd resolveParent(path: string)->{parent: *Node?, name: string}
    {
        let parts = splitPath(path)
        if parts.isEmpty() do
            return {null, ""}
        var parent = .nodeById(RootNodeId)
        if not parent do
            return {null, parts[parts.count - 1]}
        for i in 0 until parts.count - 1
        {
            parent = .findChild(parent.id, parts[i])
            if not parent or not parent.isDirectory() do
                return {null, parts[parts.count - 1]}
        }

        return {parent, parts[parts.count - 1]}
    }

    // Creates an in-memory node and leaves its journal commit to the caller.
    // The WinFsp lifecycle uses this to combine create, initial writes, and
    // cleanup metadata into one durable record.
    mtd createNodePending(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
    {
        try .requireWritable()
        let {parent, name} = .resolveParent(path)
        if parent == null or not parent.isDirectory() do
            fail volumeError(.NotFound)
        if not name.count or name == "." or name == ".." do
            fail volumeError(.InvalidInput)
        if .findChild(parent.id, name) do
            fail volumeError(.AlreadyExists)

        let now = volumeTimeNow()
        var node: Node
        node.id         = .nextNodeId
        node.parentId   = parent.id
        node.name       = name
        node.attributes = attributes
        if directory do
            node.attributes |= FileAttributeDirectory
        elif not node.attributes do
            node.attributes = FileAttributeNormal
        node.creationTime   = now
        node.lastAccessTime = now
        node.lastWriteTime  = now
        node.changeTime     = now
        node.security.add(security)
        .nextNodeId += 1
        let result = node.id
        .nodes.add(#move node)
        let indexed = .nodeLookup.add(&.nodes[.nodes.count - 1], .nodes.count - 1)
        Swag.assert(indexed)
        .touch(result)
        .scalarsDirty = true
        return result
    }

    // Creates one node as a complete durable volume operation.
    mtd createNode(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
    {
        let result = try .createNodePending(path, directory, attributes, security)
        try .commit()
        return result
    }

    mtd nodeIndex(id: u64)->u64 => .nodeLookup.nodePosition(id)

    mtd removeNodeAt(index: u64)
    {
        Swag.assert(index < .nodes.count)
        .nodeLookup.remove(&.nodes[index])
        .nodes.removeAt(index)
        if index < .nodes.count do
            .nodeLookup.updateNodePosition(.nodes[index].id, index)
    }

    mtd hasChildren(id: u64)->bool => .nodeLookup.hasChildren(id)

    // Deletes a file or an empty directory, and commits.
    mtd deleteNode(id: u64) fail
    {
        try .requireWritable()
        if id == RootNodeId do
            fail volumeError(.AccessDenied)
        let index = .nodeIndex(id)
        if index == Swag.U64.Max do
            return
        if .nodes[index].isDirectory() and .hasChildren(id) do
            fail volumeError(.DirectoryNotEmpty)
        .freeNodeBlocks(&.nodes[index])
        .removeNodeAt(index)

        // A node that is being deleted must leave the pending set, or the
        // journal record would describe a node that no longer exists.
        .drop(id)
        try .commit()
    }

    // Moves a node to `newPath`, over an existing target of the same kind when `replace` allows
    // it, and commits.
    mtd renameNode(id: u64, newPath: string, replace: bool) fail
    {
        try .requireWritable()
        if id == RootNodeId do
            fail volumeError(.AccessDenied)
        let {parent, name} = .resolveParent(newPath)
        if parent == null or not parent.isDirectory() or not name.count do
            fail volumeError(.NotFound)
        let destinationParentId = parent.id
        let sourceIsDirectory   = .nodeById(id)!.isDirectory()
        let existing = .findChild(parent.id, name)
        if existing and existing.id != id
        {
            if not replace do
                fail volumeError(.AlreadyExists)
            if existing.isDirectory() != sourceIsDirectory do
                fail volumeError(.InvalidInput)
            if existing.isDirectory() and .hasChildren(existing.id) do
                fail volumeError(.DirectoryNotEmpty)
            let existingId    = existing.id
            let existingIndex = .nodeIndex(existingId)
            .freeNodeBlocks(&.nodes[existingIndex])
            .removeNodeAt(existingIndex)
            .drop(existingId)
        }

        let node = .nodeById(id)!
        if node.isDirectory()
        {
            var ancestor = destinationParentId
            while ancestor != RootNodeId
            {
                if ancestor == id do
                    fail volumeError(.InvalidInput)
                ancestor = .nodeById(ancestor)!.parentId
            }
        }

        let updated      = .nodeById(id)!
        let indexUpdated = .nodeLookup.changeParent(updated, destinationParentId, name)
        Swag.assert(indexUpdated)
        updated.changeTime = volumeTimeNow()
        .touchMetadata(id)
        try .commit()
    }
}

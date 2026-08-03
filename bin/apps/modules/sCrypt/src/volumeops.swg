using Core

namespace SCrypt
{
    impl Volume
    {
        mtd createNode(path: string, directory: bool, attributes: u32,
                       security: const [..] u8)->u64 fail
        {
            let {parent, name} = .resolveParent(path)
            if parent == null or !(notnull parent).isDirectory() do
                failWith("Parent directory does not exist.", .NotFound)
            let validParent = notnull parent
            if !@countof(name) or name == "." or name == ".." do
                failWith("Invalid file name.", .InvalidInput)
            if .findChild(validParent.id, name) do
                failWith("A file with this name already exists.", .AlreadyExists)

            let now = volumeTimeNow()
            var node: Node
            node.id             = .nextNodeId
            node.parentId       = validParent.id
            node.name           = name
            node.attributes     = attributes
            if directory do
                node.attributes |= FileAttributeDirectory
            elif !node.attributes do
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
            Debug.assert(indexed)
            .dirty = true
            .commit()
            return result
        }

        mtd nodeIndex(id: u64)->u64
        {
            return .nodeLookup.nodePosition(id)
        }

        mtd removeNodeAt(index: u64)
        {
            Debug.assert(index < .nodes.count)
            .nodeLookup.remove(&.nodes[index])
            .nodes.removeAt(index)
            if index < .nodes.count do
                .nodeLookup.updateNodePosition(.nodes[index].id, index)
        }

        mtd hasChildren(id: u64)->bool
        {
            return .nodeLookup.hasChildren(id)
        }

        mtd deleteNode(id: u64) fail
        {
            if id == 1 do
                failWith("Cannot delete the root directory.", .AccessDenied)
            let index = .nodeIndex(id)
            if index == Swag.U64.Max do
                return
            if .nodes[index].isDirectory() and .hasChildren(id) do
                failWith("The directory is not empty.", .DirectoryNotEmpty)
            .freeNodeBlocks(&.nodes[index])
            .removeNodeAt(index)
            .dirty = true
            .commit()
        }

        mtd renameNode(id: u64, newPath: string, replace: bool) fail
        {
            if id == 1 do
                failWith("Cannot rename the root directory.", .AccessDenied)
            let {parent, name} = .resolveParent(newPath)
            if parent == null or !(notnull parent).isDirectory() or !@countof(name) do
                failWith("The destination directory does not exist.", .NotFound)
            let validParent = notnull parent
            let destinationParentId = validParent.id
            let sourceIsDirectory = (notnull .nodeById(id)).isDirectory()
            let existing = .findChild(validParent.id, name)
            if existing and existing.id != id
            {
                if !replace do
                    failWith("The destination already exists.", .AlreadyExists)
                if existing.isDirectory() != sourceIsDirectory do
                    failWith("A file cannot replace a directory, or conversely.", .InvalidInput)
                if existing.isDirectory() and .hasChildren(existing.id) do
                    failWith("The destination directory is not empty.", .DirectoryNotEmpty)
                let existingIndex = .nodeIndex(existing.id)
                .freeNodeBlocks(&.nodes[existingIndex])
                .removeNodeAt(existingIndex)
            }

            let node = notnull .nodeById(id)
            if node.isDirectory()
            {
                var ancestor = destinationParentId
                while ancestor != 1
                {
                    if ancestor == id do
                        failWith("Cannot move a directory into itself.", .InvalidInput)
                    ancestor = (notnull .nodeById(ancestor)).parentId
                }
            }
            let updated = notnull .nodeById(id)
            let indexUpdated = .nodeLookup.changeParent(updated, destinationParentId, name)
            Debug.assert(indexUpdated)
            updated.changeTime = volumeTimeNow()
            .dirty = true
            .commit()
        }

        mtd freeBytes()->u64
        {
            return .blocks.freeBlockCount() * BlockSize
        }

        mtd freeBlockCount()->u64
        {
            return .blocks.freeBlockCount()
        }

        mtd totalBytes()->u64 => .blockCount * BlockSize

    }
}

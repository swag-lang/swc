using Core

namespace SCrypt
{
    impl Volume
    {
        mtd nodeById(id: u64)->#null *Node
        {
            let index = .nodeLookup.nodePosition(id)
            return index != Swag.U64.Max ? &.nodes[index] : null
        }

        mtd findChild(parentId: u64, name: string)->#null *Node
        {
            let id = .nodeLookup.childId(parentId, name)
            return id != Swag.U64.Max ? .nodeById(id) : null
        }

        mtd resolve(path: string)->#null *Node
        {
            let parts = Tokenize.split(path, cast(u8) '\\', removeEmpty: true)
            var current = .nodeById(1)
            if !current do
                return null
            for part in parts
            {
                current = .findChild((notnull current).id, part)
                if !current do
                    return null
            }
            return current
        }

        mtd resolveParent(path: string)->{parent: #null *Node, name: string}
        {
            let parts = Tokenize.split(path, cast(u8) '\\', removeEmpty: true)
            if !parts.count do
                return {null, ""}
            var parent = .nodeById(1)
            if !parent do
                return {null, parts[parts.count - 1]}
            for [i] in 0 until parts.count - 1
            {
                parent = .findChild((notnull parent).id, parts[i])
                if !parent or !(notnull parent).isDirectory() do
                    return {null, parts[parts.count - 1]}
            }
            return {parent, parts[parts.count - 1]}
        }

        mtd readPhysical(physical: u64, destination: [..] u8) fail
        {
            Debug.assert(@countof(destination) == BlockSize)
            var record: [BlockRecordSize] u8
            if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
                failWith("The container is truncated or unreadable.", .Io)
            let nonce = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
            let tag = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
            if !Crypto.open(&.keys, DataKind, physical, nonce, ciphertext, tag, destination) do
                failWith("An encrypted data block is damaged.", .Corrupted)
        }

        mtd readBlock(node: *Node, logical: u64, destination: [..] u8) fail
        {
            @memset(@dataof(destination), 0, @countof(destination))
            let search = node.blockSearch(logical)
            if search.found do
                .readPhysical(node.blocks[search.index].physical, destination)
        }

        mtd writeBlock(nodeId, logical: u64, source: const [..] u8) fail
        {
            Debug.assert(@countof(source) == BlockSize)
            let physical = try .blocks.allocate()
            var published = false
            defer
            {
                if !published do
                    .blocks.release(physical)
            }
            var record: [BlockRecordSize] u8
            let nonce = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
            let tag = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
            Crypto.seal(&.keys, DataKind, physical, source, nonce, ciphertext, tag)
            .file.writeAllAt(DataOffset + physical * BlockRecordSize, record)

            let node = notnull .nodeById(nodeId)
            let search = node.blockSearch(logical)
            if search.found
            {
                .blocks.deferRelease(node.blocks[search.index].physical)
                node.blocks[search.index].physical = physical
            }
            else do
                node.blocks.insertAt(search.index, BlockMapping{logical, physical})
            .dirty = true
            published = true
        }

        mtd freeNodeBlocks(node: *Node)
        {
            for mapping in node.blocks do
                .blocks.deferRelease(mapping.physical)
            node.blocks.clear()
            .dirty = true
        }

        mtd trimNode(node: *Node, newSize: u64)
        {
            let keepBlocks = (newSize + BlockSize - 1) / BlockSize
            var index = node.blocks.count
            while index
            {
                index -= 1
                if node.blocks[index].logical < keepBlocks do
                    break
                .blocks.deferRelease(node.blocks[index].physical)
                node.blocks.removeAtOrdered(index)
            }
            .dirty = true
        }

        mtd zeroOldTail(nodeId, oldSize, newSize: u64) fail
        {
            if newSize <= oldSize or oldSize % BlockSize == 0 do
                return
            let node = notnull .nodeById(nodeId)
            let logical = oldSize / BlockSize
            let search = node.blockSearch(logical)
            if !search.found do
                return
            var block: [BlockSize] u8
            defer Core.Crypto.secureClear(block)
            .readPhysical(node.blocks[search.index].physical, block)
            let end = Math.min(newSize, (logical + 1) * BlockSize)
            @memset(&block[oldSize % BlockSize], 0, end - oldSize)
            .writeBlock(nodeId, logical, block)
        }

        mtd resizeNode(nodeId, newSize: u64) fail
        {
            let node = notnull .nodeById(nodeId)
            if node.isDirectory() do
                failWith("Cannot resize a directory.", .IsDirectory)
            let oldSize = node.size
            if newSize > oldSize do
                .zeroOldTail(nodeId, oldSize, newSize)
            elif newSize < oldSize do
                .trimNode(node, newSize)
            let current = notnull .nodeById(nodeId)
            current.size       = newSize
            current.changeTime = volumeTimeNow()
            current.lastWriteTime = current.changeTime
            .dirty = true
        }

        mtd readNode(nodeId: u64, offset: u64, destination: [..] u8)->u32 fail
        {
            let node = .nodeById(nodeId)
            if !node do
                failWith("File handle is no longer valid.", .NotFound)
            let validNode = notnull node
            if validNode.isDirectory() do
                failWith("Cannot read a directory as a file.", .IsDirectory)
            if offset >= validNode.size or !@countof(destination) do
                return 0

            let count = Math.min(@countof(destination), validNode.size - offset)
            var done = 0'u64
            while done < count
            {
                let absolute = offset + done
                let logical = absolute / BlockSize
                let inBlock = absolute % BlockSize
                let chunk = Math.min(count - done, BlockSize - inBlock)
                var block: [BlockSize] u8
                .readBlock(validNode, logical, block)
                @memcpy(@dataof(destination) + done, &block[inBlock], chunk)
                Core.Crypto.secureClear(block)
                done += chunk
            }
            return cast(u32) count
        }

        mtd writeNode(nodeId: u64, offset: u64, source: const [..] u8,
                      writeToEnd, constrained: bool)->u32 fail
        {
            let node = .nodeById(nodeId)
            if !node do
                failWith("File handle is no longer valid.", .NotFound)
            let validNode = notnull node
            if validNode.isDirectory() do
                failWith("Cannot write to a directory.", .IsDirectory)
            if (validNode.attributes & FileAttributeReadOnly) != 0 do
                failWith("The file is read-only.", .AccessDenied)

            var writeOffset = offset
            if writeToEnd do
                writeOffset = validNode.size
            var count = @countof(source)
            if constrained
            {
                if writeOffset >= validNode.size do
                    return 0
                count = Math.min(count, validNode.size - writeOffset)
            }
            if !count do
                return 0
            if writeOffset > Swag.U64.Max - count do
                failWith("File size overflow.", .InvalidInput)

            let oldSize = validNode.size
            let end = writeOffset + count
            if !constrained and end > oldSize do
                .zeroOldTail(nodeId, oldSize, end)

            var done = 0'u64
            while done < count
            {
                let absolute = writeOffset + done
                let logical = absolute / BlockSize
                let inBlock = absolute % BlockSize
                let chunk = Math.min(count - done, BlockSize - inBlock)
                let current = notnull .nodeById(nodeId)
                var block: [BlockSize] u8
                if inBlock or chunk != BlockSize do
                    .readBlock(current, logical, block)
                @memcpy(&block[inBlock], @dataof(source) + done, chunk)
                .writeBlock(nodeId, logical, block)
                Core.Crypto.secureClear(block)
                done += chunk
            }

            let updated = notnull .nodeById(nodeId)
            if end > updated.size do
                updated.size = end
            let now = volumeTimeNow()
            updated.lastWriteTime = now
            updated.changeTime    = now
            updated.attributes   |= FileAttributeArchive
            .dirty = true
            return cast(u32) count
        }
    }
}

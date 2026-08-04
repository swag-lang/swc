using Core

// Serialized timestamps use 100-nanosecond ticks since 1601-01-01 UTC.
// Keeping the epoch in the format layer preserves compatibility with existing volumes.
const VolumeTimestampEpoch = 504_911_232_000_000_000'u64

func volumeTimeNow()->u64
{
    return Time.Timestamp.utcNow().ticks - VolumeTimestampEpoch
}

const FileAttributeReadOnly  = 0x00000001'u32
const FileAttributeDirectory = 0x00000010'u32
const FileAttributeArchive   = 0x00000020'u32
const FileAttributeNormal    = 0x00000080'u32

#[Swag.NoCopy]
struct Volume
{
    file:          File.FileStream
    keys:          Crypto.Keys
    path:          String
    label:         String
    containerSize: u64
    blockCount:    u64
    sequence:      u64
    nextNodeId:    u64
    activeSlot:    u32
    nodes:         Array'Node
    nodeLookup:    NodeIndex
    blocks:        BlockAllocator
    dirty:         bool
}

impl Volume
{
    mtd close()
    {
        if .file.isOpen()
        {
            .file.close()
        }

        .dirty = false
        .keys.clear()
    }

    mtd opDrop()
    {
        .close()
    }

    func create(path: string, password: const [..] u8, requestedSize: u64)->Volume fail
    {
        if !@countof(password) do
            failWith("A password is required.", .InvalidInput)
        if requestedSize < MinimumSize do
            failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .InvalidInput)

        var result: retval
        var created   = false
        var completed = false

        // `completed` is set only on the last line, so any failure below unwinds
        // everything and leaves no half-written container on disk.
        defer
        {
            if !completed
            {
                result.close()
                if created do
                    discard catch File.delete(path)
            }
        }

        with result
        {
            .dirty         = false
            .activeSlot    = 0
            .sequence      = 0
            .path          = path
            .containerSize = requestedSize
            .blockCount    = (requestedSize - DataOffset) / BlockRecordSize
            .nextNodeId    = RootNodeId + 1
            .label         = "sCrypt"
        }

        result.file = File.open(path, .CreateNew, .ReadWrite, .Read)
        created     = true
        result.file.resize(requestedSize)

        // Fill the whole container with random bytes before anything real is
        // written. Encrypted blocks are indistinguishable from random, so this is
        // what stops an observer from telling which blocks are in use, or how
        // much of the container holds data.
        var randomChunk: Array'u8
        randomChunk.resize(RandomizeChunkSize)
        var offset = 0'u64
        while offset < requestedSize
        {
            let count = Math.min(requestedSize - offset, randomChunk.count)
            Core.Crypto.randomBytes(randomChunk[0 until count])
            result.file.writeAllAt(offset, randomChunk[0 until count])
            offset += count
        }

        Core.Crypto.secureClear(randomChunk.toSlice())

        // The salt is public and lives at offset 0; the keys derived from it
        // never touch the disk.
        var salt: [Crypto.SaltSize] u8
        Core.Crypto.randomBytes(salt)
        result.file.writeAllAt(0, salt)
        result.keys = Crypto.deriveKeys(password, salt)
        Core.Crypto.secureClear(salt)

        // The root directory is its own parent, which ends every path walk.
        let now = volumeTimeNow()
        with var root: Node
        {
            .id             = RootNodeId
            .parentId       = RootNodeId
            .name           = ""
            .attributes     = FileAttributeDirectory
            .creationTime   = now
            .lastAccessTime = now
            .lastWriteTime  = now
            .changeTime     = now
        }

        result.nodes.add(#move root)
        let rootIndexed = result.nodeLookup.add(&result.nodes[0], 0)
        Debug.assert(rootIndexed)

        result.blocks.initialize(result.blockCount)
        result.dirty = true
        result.commit()

        completed = true
        return result
    }

    func open(path: string, password: const [..] u8)->Volume fail
    {
        if !@countof(password) do
            failWith("A password is required.", .InvalidInput)

        var result: retval
        result.dirty = false
        result.path  = path
        result.file  = File.open(path, .Open, .ReadWrite, .Read)
        var completed = false
        defer
        {
            if !completed do
                result.close()
        }

        result.containerSize = result.file.size()
        if result.containerSize < MinimumSize do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        var salt: [Crypto.SaltSize] u8
        if !result.file.readExactAt(0, salt) do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)
        result.keys = Crypto.deriveKeys(password, salt)
        Core.Crypto.secureClear(salt)

        var first = result.readHeader(0)
        defer Core.Crypto.secureClear(first.plain.toSlice())
        var second = result.readHeader(1)
        defer Core.Crypto.secureClear(second.plain.toSlice())
        var selected: #null *HeaderCandidate
        if first.valid and second.valid do
            selected = first.sequence >= second.sequence ? &first : &second
        elif first.valid do
            selected = &first
        elif second.valid do
            selected = &second
        else do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        let validHeader = notnull selected
        result.activeSlot = validHeader == &first ? 0 : 1

        // Every way the metadata can be rejected reports the same thing: a
        // caller must not be able to tell a wrong password from a damaged
        // container, or from which field gave up first.
        discard catch result.deserialize(validHeader.plain.toSlice()) as parseError
        if parseError != null do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        completed = true
        return result
    }

    mtd readHeader(slot: u32)->HeaderCandidate fail
    {
        var result: retval
        let offset = Crypto.SaltSize + slot * HeaderSlotSize
        var prefix: [Crypto.RecordLocatorSize] u8
        if !.file.readExactAt(offset, prefix) do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        var locator = Crypto.recordLocator(.keys.authentication, HeaderLocatorKind, slot)
        defer Core.Crypto.secureClear(locator)
        if Core.Crypto.constantTimeEqual(prefix[until HeaderLocatorCheckSize], locator[until HeaderLocatorCheckSize])
        {
            let plainSize = Crypto.load32(&prefix[HeaderLocatorCheckSize]) ^ Crypto.load32(&locator[HeaderLocatorCheckSize])
            if !plainSize or plainSize > HeaderPlainSize do
                return result

            var record: Array'u8
            record.resize(Crypto.NonceSize + plainSize + Crypto.TagSize)
            if !.file.readExactAt(offset + #sizeof(prefix), record.toSlice()) do
                return result
            result.plain.resize(plainSize)
            let nonce      = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + plainSize]
            let tag        = record[Crypto.NonceSize + plainSize until @countof(record)]
            if !Crypto.open(&.keys, HeaderKind, slot, nonce, ciphertext, tag, result.plain.toSlice()) do
                return result
        }
        else
        {
            var record: Array'u8
            record.resize(HeaderSlotSize)
            @memcpy(record.buffer, &prefix[0], #sizeof(prefix))
            if !.file.readExactAt(offset + #sizeof(prefix), record[#sizeof(prefix) until HeaderSlotSize]) do
                return result
            result.plain.resize(LegacyHeaderPlainSize)
            let nonce      = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + LegacyHeaderPlainSize]
            let tag        = record[Crypto.NonceSize + LegacyHeaderPlainSize until HeaderSlotSize]
            if !Crypto.open(&.keys, HeaderKind, slot, nonce, ciphertext, tag, result.plain.toSlice()) do
                return result
        }

        let sequence = catch parseHeaderSequence(result.plain.toSlice()) as parseError
        if parseError != null do
            return result

        result.sequence = sequence
        result.valid    = true
        return result
    }

    // Serializes the volume metadata into the plaintext of a header slot.
    //
    // Block mappings are stored as runs of contiguous logical/physical pairs,
    // which keeps a large defragmented file down to a single record.
    mtd serialize(sequence: u64)->Array'u8 fail
    {
        var result: retval
        var writer = ByteStream.openWrite(&result)

        writer.writeBytes(HeaderMagic)
        writer.writeLittleEndian(FormatVersion)
        writer.writeLittleEndian(sequence)
        writer.writeLittleEndian(.containerSize)
        writer.writeLittleEndian(.blockCount)
        writer.writeLittleEndian(.nextNodeId)
        writer.writeSizedString(.label)

        writer.writeLittleEndian(.nodes.count)
        for node in .nodes
        {
            writer.writeLittleEndian(node.id)
            writer.writeLittleEndian(node.parentId)
            writer.writeSizedString(node.name)
            writer.writeLittleEndian(node.attributes)
            writer.writeLittleEndian(node.size)
            writer.writeLittleEndian(node.creationTime)
            writer.writeLittleEndian(node.lastAccessTime)
            writer.writeLittleEndian(node.lastWriteTime)
            writer.writeLittleEndian(node.changeTime)
            writer.writeLittleEndian(cast(u32) node.security.count)
            writer.writeBytes(node.security.toSlice())

            writer.writeLittleEndian(node.runCount())
            var index = 0'u64
            while index < node.blocks.count
            {
                let count = node.runLength(index)
                writer.writeLittleEndian(node.blocks[index].logical)
                writer.writeLittleEndian(node.blocks[index].physical)
                writer.writeLittleEndian(count)
                index += count
            }
        }

        writer.writeLittleEndian(.blocks.free.count)
        for extent in .blocks.free
        {
            writer.writeLittleEndian(extent.first)
            writer.writeLittleEndian(extent.count)
        }

        // The header slot has a fixed size, so an oversized metadata block is a
        // real out-of-space condition rather than a corruption.
        if result.count > HeaderPlainSize do
            failWith("The encrypted metadata area is full.", .DiskFull)
        return result
    }

    // Rebuilds the volume metadata from the plaintext of a header slot.
    //
    // Every field is attacker-controlled once the password is known, so each
    // count and block index is validated against the container geometry before
    // it is used to size an allocation. Callers report any failure as a single
    // "wrong password or damaged container" outcome; see `Volume.open`.
    mtd deserialize(plain: const [..] u8) fail
    {
        var reader = ByteStream.openRead(plain)

        var magic: [#sizeof(HeaderMagic)] u8
        reader.readBytes(&magic[0], #sizeof(magic))
        if @memcmp(&magic[0], &HeaderMagic[0], #sizeof(magic)) != 0 do
            failWith("The container does not start with an sCrypt header.", .Corrupted)

        let version = reader.readLittleEndian'u32()
        if version != LegacyFormatVersion and version != FormatVersion do
            failWith("The container format version is not supported.", .Corrupted)

        .sequence = reader.readLittleEndian'u64()
        let storedSize = reader.readLittleEndian'u64()
        .blockCount = reader.readLittleEndian'u64()
        .nextNodeId = reader.readLittleEndian'u64()
        .label      = reader.readSizedString(MaximumLabelSize)
        if storedSize != .containerSize or .blockCount != (.containerSize - DataOffset) / BlockRecordSize do
            failWith("The container geometry does not match its size.", .Corrupted)

        let nodeCount = reader.readLittleEndian'u64()
        if !nodeCount or nodeCount > MaximumNodeCount do
            failWith("The container declares an implausible number of entries.", .Corrupted)

        .nodes.reserve(nodeCount)
        var totalMappings = 0'u64
        for nodeCount
        {
            var node: Node
            node.id             = reader.readLittleEndian'u64()
            node.parentId       = reader.readLittleEndian'u64()
            node.name           = reader.readSizedString(MaximumNameSize)
            node.attributes     = reader.readLittleEndian'u32()
            node.size           = reader.readLittleEndian'u64()
            node.creationTime   = reader.readLittleEndian'u64()
            node.lastAccessTime = reader.readLittleEndian'u64()
            node.lastWriteTime  = reader.readLittleEndian'u64()
            node.changeTime     = reader.readLittleEndian'u64()

            let securitySize = reader.readLittleEndian'u32()
            if securitySize > MaximumSecuritySize do
                failWith("An entry declares an implausible security descriptor.", .Corrupted)
            node.security.resize(securitySize)
            reader.readBytes(node.security.buffer, securitySize)

            let runCount = reader.readLittleEndian'u64()
            if runCount > .blockCount do
                failWith("An entry declares more block runs than the container holds.", .Corrupted)

            for runCount
            {
                let logical  = reader.readLittleEndian'u64()
                let physical = reader.readLittleEndian'u64()
                let count    = reader.readLittleEndian'u64()
                if !count or physical >= .blockCount or count > .blockCount - physical or count > .blockCount - totalMappings do
                    failWith("A block run falls outside the container.", .Corrupted)

                node.blocks.reserve(node.blocks.count + count)
                for [i] in count do
                    node.blocks.add({logical + i, physical + i})
                totalMappings += count
            }

            let nodeIndex = .nodes.count
            .nodes.add(#move node)
            if !.nodeLookup.add(&.nodes[nodeIndex], nodeIndex) do
                failWith("The container contains a duplicate entry.", .Corrupted)
        }

        let freeCount = reader.readLittleEndian'u64()
        if freeCount > .blockCount do
            failWith("The free list is larger than the container.", .Corrupted)

        .blocks.free.reserve(freeCount)
        for freeCount
        {
            let first = reader.readLittleEndian'u64()
            let count = reader.readLittleEndian'u64()
            if !count or first >= .blockCount or count > .blockCount - first do
                failWith("A free extent falls outside the container.", .Corrupted)
            .blocks.free.add({first, count})
        }

        if .nodeById(RootNodeId) == null do
            failWith("The container has no root directory.", .Corrupted)
        .dirty = false
    }

    mtd commit() fail
    {
        if !.dirty do
            return

        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())
        var committed = false
        defer
        {
            if !committed do
                .blocks.free = #move previousFree
        }

        .blocks.publishDeferred()

        let newSequence = .sequence + 1
        let slot        = 1'u32 - .activeSlot
        var plain       = .serialize(newSequence)
        defer Core.Crypto.secureClear(plain.toSlice())
        var record: Array'u8
        record.resize(HeaderRecordPrefixSize + @countof(plain) + Crypto.TagSize)
        var locator = Crypto.recordLocator(.keys.authentication, HeaderLocatorKind, slot)
        defer Core.Crypto.secureClear(locator)
        @memcpy(record.buffer, &locator[0], HeaderLocatorCheckSize)
        Crypto.store32(notnull record.buffer + HeaderLocatorCheckSize, cast(u32) @countof(plain) ^ Crypto.load32(&locator[HeaderLocatorCheckSize]))
        let nonce      = record[Crypto.RecordLocatorSize until HeaderRecordPrefixSize]
        let ciphertext = record[HeaderRecordPrefixSize until HeaderRecordPrefixSize + @countof(plain)]
        let tag        = record[HeaderRecordPrefixSize + @countof(plain) until @countof(record)]
        Crypto.seal(&.keys, HeaderKind, slot, plain.toSlice(), nonce, ciphertext, tag)
        .file.writeAllAt(Crypto.SaltSize + slot * HeaderSlotSize, record.toSlice())
        .file.flush()
        .blocks.completeCommit()
        .sequence   = newSequence
        .activeSlot = slot
        .dirty      = false
        committed   = true
    }

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
        let parts   = Tokenize.split(path, cast(u8) '\\', removeEmpty: true)
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
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
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
        let physical  = try .blocks.allocate()
        var published = false
        defer
        {
            if !published do
                .blocks.release(physical)
        }

        var record: [BlockRecordSize] u8
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        Crypto.seal(&.keys, DataKind, physical, source, nonce, ciphertext, tag)
        .file.writeAllAt(DataOffset + physical * BlockRecordSize, record)

        let node   = notnull .nodeById(nodeId)
        let search = node.blockSearch(logical)
        if search.found
        {
            .blocks.deferRelease(node.blocks[search.index].physical)
            node.blocks[search.index].physical = physical
        }
        else do
            node.blocks.insertAt(search.index, BlockMapping{logical, physical})
        .dirty    = true
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
        var index      = node.blocks.count
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
        let node    = notnull .nodeById(nodeId)
        let logical = oldSize / BlockSize
        let search  = node.blockSearch(logical)
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
        current.size          = newSize
        current.changeTime    = volumeTimeNow()
        current.lastWriteTime = current.changeTime
        .dirty                = true
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
        var done  = 0'u64
        while done < count
        {
            let absolute = offset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)
            var block: [BlockSize] u8
            .readBlock(validNode, logical, block)
            @memcpy(@dataof(destination) + done, &block[inBlock], chunk)
            Core.Crypto.secureClear(block)
            done += chunk
        }

        return cast(u32) count
    }

    mtd writeNode(nodeId: u64, offset: u64, source: const [..] u8, writeToEnd, constrained: bool)->u32 fail
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
        let end     = writeOffset + count
        if !constrained and end > oldSize do
            .zeroOldTail(nodeId, oldSize, end)

        var done = 0'u64
        while done < count
        {
            let absolute = writeOffset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)
            let current  = notnull .nodeById(nodeId)
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
        updated.attributes    |= FileAttributeArchive
        .dirty                = true
        return cast(u32) count
    }

    mtd createNode(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
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
        node.id         = .nextNodeId
        node.parentId   = validParent.id
        node.name       = name
        node.attributes = attributes
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
        let validParent         = notnull parent
        let destinationParentId = validParent.id
        let sourceIsDirectory   = (notnull .nodeById(id)).isDirectory()
        let existing            = .findChild(validParent.id, name)
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

        let updated      = notnull .nodeById(id)
        let indexUpdated = .nodeLookup.changeParent(updated, destinationParentId, name)
        Debug.assert(indexUpdated)
        updated.changeTime = volumeTimeNow()
        .dirty             = true
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

using Core

namespace SCrypt
{
    const BlockSize       = 4096'u64
    const BlockRecordSize = BlockSize + Crypto.NonceSize + Crypto.TagSize
    const HeaderSlotSize  = #command == Swag.CompilerCommand.Test ?
                            256'u64 * 1024 : 8'u64 * 1024 * 1024
    const HeaderPlainSize = HeaderSlotSize - Crypto.NonceSize - Crypto.TagSize
    const HeaderSlotCount = 2'u64
    const DataOffset      = Crypto.SaltSize + HeaderSlotCount * HeaderSlotSize
    const MinimumBlocks   = 16'u64
    const MinimumSize     = DataOffset + MinimumBlocks * BlockRecordSize
    const FormatVersion   = 1'u32
    const HeaderKind      = 1'u32
    const DataKind        = 2'u32

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

    const CleanupDelete            = 0x01'u32
    const CleanupSetAllocationSize = 0x02'u32
    const CleanupSetArchiveBit     = 0x10'u32
    const CleanupSetLastAccessTime = 0x20'u32
    const CleanupSetLastWriteTime  = 0x40'u32
    const CleanupSetChangeTime     = 0x80'u32

    const StatusSuccess             = 0's32
    const StatusBufferOverflow      = cast #bit (s32) 0x80000005'u32
    const StatusInvalidParameter    = cast #bit (s32) 0xC000000D'u32
    const StatusAccessDenied        = cast #bit (s32) 0xC0000022'u32
    const StatusObjectNameNotFound  = cast #bit (s32) 0xC0000034'u32
    const StatusObjectNameCollision = cast #bit (s32) 0xC0000035'u32
    const StatusDiskFull            = cast #bit (s32) 0xC000007F'u32
    const StatusFileIsDirectory     = cast #bit (s32) 0xC00000BA'u32
    const StatusDirectoryNotEmpty   = cast #bit (s32) 0xC0000101'u32
    const StatusNotADirectory       = cast #bit (s32) 0xC0000103'u32
    const StatusIoDeviceError       = cast #bit (s32) 0xC0000185'u32

    const HeaderMagic: [16] u8 = [
        0x73, 0x43, 0x72, 0x79, 0x70, 0x74, 0x2D, 0x56,
        0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x2D, 0x31, 0x00]

    struct BlockMapping
    {
        logical:  u64
        physical: u64
    }

    struct FreeExtent
    {
        first: u64
        count: u64
    }

    struct Node
    {
        id:             u64
        parentId:       u64
        name:           String
        attributes:     u32
        size:           u64
        creationTime:   u64
        lastAccessTime: u64
        lastWriteTime:  u64
        changeTime:     u64
        blocks:         Array'BlockMapping
        security:       Array'u8
    }

    impl Node
    {
        mtd isDirectory()->bool => (.attributes & FileAttributeDirectory) != 0

        mtd blockSearch(logical: u64)->{found: bool, index: u64}
        {
            var low = 0'u64
            var high = .blocks.count
            while low < high
            {
                let middle = low + (high - low) / 2
                if .blocks[middle].logical < logical do
                    low = middle + 1
                else do
                    high = middle
            }
            return {low < .blocks.count and .blocks[low].logical == logical, low}
        }
    }

    struct ByteWriter
    {
        buffer: Array'u8
        cursor: u64
    }

    impl ByteWriter
    {
        func create(capacity: u64)->ByteWriter
        {
            var result: retval
            result.buffer.resize(capacity)
            return result
        }

        mtd require(count: u64) fail
        {
            if count > .buffer.count - .cursor do
                failWith("The encrypted metadata area is full.")
        }

        mtd bytes(value: const [..] u8) fail
        {
            .require(@countof(value))
            @memcpy(.buffer.buffer + .cursor, @dataof(value), @countof(value))
            .cursor += @countof(value)
        }

        mtd writeU8(value: u8) fail
        {
            .require(1)
            .buffer[.cursor] = value
            .cursor += 1
        }

        mtd writeU32(value: u32) fail
        {
            .require(4)
            Crypto.store32(notnull .buffer.buffer + .cursor, value)
            .cursor += 4
        }

        mtd writeU64(value: u64) fail
        {
            .writeU32(Crypto.low32(value))
            .writeU32(Crypto.low32(value >> 32))
        }

        mtd writeString(value: string) fail
        {
            if @countof(value) > Swag.U32.Max do
                failWith("A metadata string is too large.")
            .writeU32(cast(u32) @countof(value))
            .bytes(@mkslice(@dataof(value), @countof(value)))
        }
    }

    struct ByteReader
    {
        data:   const [..] u8
        cursor: u64
        valid = true
    }

    impl ByteReader
    {
        mtd has(count: u64)->bool => .valid and count <= @countof(.data) - .cursor

        mtd readU8()->u8
        {
            if !.has(1)
            {
                .valid = false
                return 0
            }
            let result = .data[.cursor]
            .cursor += 1
            return result
        }

        mtd readU32()->u32
        {
            if !.has(4)
            {
                .valid = false
                return 0
            }
            let result = Crypto.load32(@dataof(.data) + .cursor)
            .cursor += 4
            return result
        }

        mtd readU64()->u64
        {
            let low = .readU32()
            let high = .readU32()
            return low | (cast(u64) high << 32)
        }

        mtd readString(maxLength = 1'u64 * 1024 * 1024)->String
        {
            let length = .readU32()
            if length > maxLength or !.has(length)
            {
                .valid = false
                return {}
            }
            var result: retval
            result = @mkstring(@dataof(.data) + .cursor, length)
            .cursor += length
            return result
        }

        mtd matches(value: const [..] u8)->bool
        {
            if !.has(@countof(value)) do
                return false
            let result = @memcmp(@dataof(.data) + .cursor, @dataof(value), @countof(value)) == 0
            .cursor += @countof(value)
            return result
        }
    }

    struct HeaderCandidate
    {
        valid:    bool
        sequence: u64
        plain:    Array'u8
    }

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
        free:          Array'FreeExtent
        deferredFree:  Array'u64
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
                failWith("A password is required.")
            if requestedSize < MinimumSize do
                failWith(Format.toString("The container must be at least % bytes.", MinimumSize))

            var result: retval
            var created   = false
            var completed = false
            defer
            {
                if !completed
                {
                    result.close()
                    if created do
                        discard catch File.delete(path)
                }
            }

            result.dirty         = false
            result.activeSlot    = 0
            result.sequence      = 0
            result.path          = path
            result.containerSize = requestedSize
            result.blockCount    = (requestedSize - DataOffset) / BlockRecordSize
            result.nextNodeId    = 2
            result.label         = "sCrypt"
            result.file          = File.open(path, .CreateNew, .ReadWrite, .Read)
            created = true
            result.file.resize(requestedSize)

            var randomChunk: Array'u8
            randomChunk.resize(1024 * 1024)
            var offset = 0'u64
            while offset < requestedSize
            {
                let count = Math.min(requestedSize - offset, randomChunk.count)
                Core.Crypto.randomBytes(randomChunk[0 until count])
                result.file.writeAllAt(offset, randomChunk[0 until count])
                offset += count
            }
            Core.Crypto.secureClear(randomChunk.toSlice())

            var salt: [Crypto.SaltSize] u8
            Core.Crypto.randomBytes(salt)
            result.file.writeAllAt(0, salt)
            result.keys = Crypto.deriveKeys(password, salt)
            Core.Crypto.secureClear(salt)

            let now = volumeTimeNow()
            var root: Node
            root.id             = 1
            root.parentId       = 1
            root.name           = ""
            root.attributes     = FileAttributeDirectory
            root.creationTime   = now
            root.lastAccessTime = now
            root.lastWriteTime  = now
            root.changeTime     = now
            result.nodes.add(#move root)
            result.free.add({0, result.blockCount})
            result.dirty = true
            result.commit()

            completed = true
            return result
        }

        func open(path: string, password: const [..] u8)->Volume fail
        {
            if !@countof(password) do
                failWith("A password is required.")

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
                failWith("The password is incorrect or the container is damaged.")

            var salt: [Crypto.SaltSize] u8
            if !result.file.readExactAt(0, salt) do
                failWith("The password is incorrect or the container is damaged.")
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
                failWith("The password is incorrect or the container is damaged.")

            let validHeader = notnull selected
            result.activeSlot = validHeader == &first ? 0 : 1
            result.deserialize(validHeader.plain.toSlice())
            completed = true
            return result
        }

        mtd readHeader(slot: u32)->HeaderCandidate fail
        {
            var record: Array'u8
            record.resize(HeaderSlotSize)
            if !.file.readExactAt(Crypto.SaltSize + slot * HeaderSlotSize, record.toSlice()) do
                failWith("The password is incorrect or the container is damaged.")

            var result: retval
            result.plain.resize(HeaderPlainSize)
            let nonce = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + HeaderPlainSize]
            let tag = record[Crypto.NonceSize + HeaderPlainSize until HeaderSlotSize]
            if !Crypto.open(&.keys, HeaderKind, slot, nonce, ciphertext, tag, result.plain.toSlice()) do
                return result

            var reader = ByteReader{result.plain.toSlice()}
            if !reader.matches(HeaderMagic) or reader.readU32() != FormatVersion do
                return result
            result.sequence = reader.readU64()
            result.valid    = reader.valid
            return result
        }

        mtd serialize(sequence: u64)->Array'u8 fail
        {
            var writer = ByteWriter.create(HeaderPlainSize)
            writer.bytes(HeaderMagic)
            writer.writeU32(FormatVersion)
            writer.writeU64(sequence)
            writer.writeU64(.containerSize)
            writer.writeU64(.blockCount)
            writer.writeU64(.nextNodeId)
            writer.writeString(.label)
            writer.writeU64(.nodes.count)
            for node in .nodes
            {
                writer.writeU64(node.id)
                writer.writeU64(node.parentId)
                writer.writeString(node.name)
                writer.writeU32(node.attributes)
                writer.writeU64(node.size)
                writer.writeU64(node.creationTime)
                writer.writeU64(node.lastAccessTime)
                writer.writeU64(node.lastWriteTime)
                writer.writeU64(node.changeTime)
                writer.writeU32(cast(u32) node.security.count)
                writer.bytes(node.security.toSlice())

                var runCount = 0'u64
                var idx = 0'u64
                while idx < node.blocks.count
                {
                    runCount += 1
                    var count = 1'u64
                    while idx + count < node.blocks.count and
                          node.blocks[idx + count].logical == node.blocks[idx].logical + count and
                          node.blocks[idx + count].physical == node.blocks[idx].physical + count do
                        count += 1
                    idx += count
                }
                writer.writeU64(runCount)
                idx = 0
                while idx < node.blocks.count
                {
                    var count = 1'u64
                    while idx + count < node.blocks.count and
                          node.blocks[idx + count].logical == node.blocks[idx].logical + count and
                          node.blocks[idx + count].physical == node.blocks[idx].physical + count do
                        count += 1
                    writer.writeU64(node.blocks[idx].logical)
                    writer.writeU64(node.blocks[idx].physical)
                    writer.writeU64(count)
                    idx += count
                }
            }

            writer.writeU64(.free.count)
            for extent in .free
            {
                writer.writeU64(extent.first)
                writer.writeU64(extent.count)
            }
            return writer.buffer
        }

        mtd deserialize(plain: const [..] u8) fail
        {
            var reader = ByteReader{plain}
            if !reader.matches(HeaderMagic) or reader.readU32() != FormatVersion do
                failWith("The password is incorrect or the container is damaged.")

            .sequence = reader.readU64()
            let storedSize = reader.readU64()
            .blockCount = reader.readU64()
            .nextNodeId = reader.readU64()
            .label = reader.readString(128)
            if storedSize != .containerSize or .blockCount != (.containerSize - DataOffset) / BlockRecordSize do
                failWith("The password is incorrect or the container is damaged.")

            let nodeCount = reader.readU64()
            if nodeCount == 0 or nodeCount > 1_000_000 do
                failWith("The password is incorrect or the container is damaged.")
            .nodes.reserve(nodeCount)
            var totalMappings = 0'u64
            for [nodeIndex] in nodeCount
            {
                var node: Node
                node.id             = reader.readU64()
                node.parentId       = reader.readU64()
                node.name           = reader.readString(4 * 1024)
                node.attributes     = reader.readU32()
                node.size           = reader.readU64()
                node.creationTime   = reader.readU64()
                node.lastAccessTime = reader.readU64()
                node.lastWriteTime  = reader.readU64()
                node.changeTime     = reader.readU64()
                let securitySize = reader.readU32()
                if securitySize > 1024 * 1024 or !reader.has(securitySize)
                {
                    reader.valid = false
                    break
                }
                node.security.resize(securitySize)
                if securitySize do
                    @memcpy(node.security.buffer, @dataof(plain) + reader.cursor, securitySize)
                reader.cursor += securitySize

                let runCount = reader.readU64()
                if runCount > .blockCount
                {
                    reader.valid = false
                    break
                }
                for [runIndex] in runCount
                {
                    let logical = reader.readU64()
                    let physical = reader.readU64()
                    let count = reader.readU64()
                    if !count or physical >= .blockCount or count > .blockCount - physical or
                       count > .blockCount - totalMappings
                    {
                        reader.valid = false
                        break
                    }
                    node.blocks.reserve(node.blocks.count + count)
                    for [i] in count do
                        node.blocks.add({logical + i, physical + i})
                    totalMappings += count
                }
                .nodes.add(#move node)
            }

            let freeCount = reader.readU64()
            if freeCount > .blockCount do
                reader.valid = false
            else
            {
                .free.reserve(freeCount)
                for [i] in freeCount
                {
                    let first = reader.readU64()
                    let count = reader.readU64()
                    if !count or first >= .blockCount or count > .blockCount - first
                    {
                        reader.valid = false
                        break
                    }
                    .free.add({first, count})
                }
            }

            if !reader.valid or .nodeById(1) == null do
                failWith("The password is incorrect or the container is damaged.")
            .dirty = false
        }

        mtd mergeFreeBlock(block: u64)
        {
            var index = 0'u64
            while index < .free.count and .free[index].first < block do
                index += 1

            if index and .free[index - 1].first + .free[index - 1].count == block
            {
                .free[index - 1].count += 1
                if index < .free.count and block + 1 == .free[index].first
                {
                    .free[index - 1].count += .free[index].count
                    .free.removeAtOrdered(index)
                }
                return
            }
            if index < .free.count and block + 1 == .free[index].first
            {
                .free[index].first -= 1
                .free[index].count += 1
                return
            }
            .free.insertAt(index, FreeExtent{block, 1})
        }

        mtd commit() fail
        {
            if !.dirty do
                return

            var previousFree: Array'FreeExtent
            previousFree.add(.free.toSlice())
            var committed = false
            defer
            {
                if !committed do
                    .free = #move previousFree
            }
            for block in .deferredFree do
                .mergeFreeBlock(block)

            let newSequence = .sequence + 1
            let slot = 1'u32 - .activeSlot
            var plain = .serialize(newSequence)
            defer Core.Crypto.secureClear(plain.toSlice())
            var record: Array'u8
            record.resize(HeaderSlotSize)
            let nonce = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + HeaderPlainSize]
            let tag = record[Crypto.NonceSize + HeaderPlainSize until HeaderSlotSize]
            Crypto.seal(&.keys, HeaderKind, slot, plain.toSlice(), nonce, ciphertext, tag)
            .file.writeAllAt(Crypto.SaltSize + slot * HeaderSlotSize, record.toSlice())
            .file.flush()
            .deferredFree.clear()
            .sequence   = newSequence
            .activeSlot = slot
            .dirty      = false
            committed   = true
        }

        mtd nodeById(id: u64)->#null *Node
        {
            for node, [index] in .nodes where node.id == id do
                return &.nodes[index]
            return null
        }

        mtd findChild(parentId: u64, name: string)->#null *Node
        {
            for node, [index] in .nodes where node.parentId == parentId and node.id != 1
            {
                if Utf8.compare(node.name.toSlice(), @mkslice(@dataof(name), @countof(name)), .UnicodeNoCase) == 0 do
                    return &.nodes[index]
            }
            return null
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

        mtd allocateBlock()->u64 fail
        {
            if !.free.count do
                failWith("The virtual disk is full.")
            let result = .free[0].first
            .free[0].first += 1
            .free[0].count -= 1
            if !.free[0].count do
                .free.removeAtOrdered(0)
            return result
        }

        mtd readPhysical(physical: u64, destination: [..] u8) fail
        {
            Debug.assert(@countof(destination) == BlockSize)
            var record: [BlockRecordSize] u8
            if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
                failWith("The container is truncated or unreadable.")
            let nonce = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
            let tag = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
            if !Crypto.open(&.keys, DataKind, physical, nonce, ciphertext, tag, destination) do
                failWith("An encrypted data block is damaged.")
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
            let physical = .allocateBlock()
            var published = false
            defer
            {
                if !published do
                    .mergeFreeBlock(physical)
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
                .deferredFree.add(node.blocks[search.index].physical)
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
                .deferredFree.add(mapping.physical)
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
                .deferredFree.add(node.blocks[index].physical)
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
                failWith("Cannot resize a directory.")
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
                failWith("File handle is no longer valid.")
            let validNode = notnull node
            if validNode.isDirectory() do
                failWith("Cannot read a directory as a file.")
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
                failWith("File handle is no longer valid.")
            let validNode = notnull node
            if validNode.isDirectory() do
                failWith("Cannot write to a directory.")
            if (validNode.attributes & FileAttributeReadOnly) != 0 do
                failWith("The file is read-only.")

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
                failWith("File size overflow.")

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

        mtd createNode(path: string, directory: bool, attributes: u32,
                       security: const [..] u8)->u64 fail
        {
            let {parent, name} = .resolveParent(path)
            if !parent or !parent.isDirectory() do
                failWith("Parent directory does not exist.")
            let validParent = notnull parent
            if !@countof(name) or name == "." or name == ".." do
                failWith("Invalid file name.")
            if .findChild(validParent.id, name) do
                failWith("A file with this name already exists.")

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
            .dirty = true
            .commit()
            return result
        }

        mtd nodeIndex(id: u64)->u64
        {
            for node, [index] in .nodes where node.id == id do
                return index
            return Swag.U64.Max
        }

        mtd hasChildren(id: u64)->bool
        {
            for node in .nodes where node.parentId == id and node.id != id do
                return true
            return false
        }

        mtd deleteNode(id: u64) fail
        {
            if id == 1 do
                failWith("Cannot delete the root directory.")
            let index = .nodeIndex(id)
            if index == Swag.U64.Max do
                return
            if .nodes[index].isDirectory() and .hasChildren(id) do
                failWith("The directory is not empty.")
            .freeNodeBlocks(&.nodes[index])
            .nodes.removeAtOrdered(index)
            .dirty = true
            .commit()
        }

        mtd renameNode(id: u64, newPath: string, replace: bool) fail
        {
            if id == 1 do
                failWith("Cannot rename the root directory.")
            let {parent, name} = .resolveParent(newPath)
            if !parent or !parent.isDirectory() or !@countof(name) do
                failWith("The destination directory does not exist.")
            let validParent = notnull parent
            let destinationParentId = validParent.id
            let sourceIsDirectory = (notnull .nodeById(id)).isDirectory()
            let existing = .findChild(validParent.id, name)
            if existing and existing.id != id
            {
                if !replace do
                    failWith("The destination already exists.")
                if existing.isDirectory() != sourceIsDirectory do
                    failWith("A file cannot replace a directory, or conversely.")
                if existing.isDirectory() and .hasChildren(existing.id) do
                    failWith("The destination directory is not empty.")
                let existingIndex = .nodeIndex(existing.id)
                .freeNodeBlocks(&.nodes[existingIndex])
                .nodes.removeAtOrdered(existingIndex)
            }

            let node = notnull .nodeById(id)
            if node.isDirectory()
            {
                var ancestor = destinationParentId
                while ancestor != 1
                {
                    if ancestor == id do
                        failWith("Cannot move a directory into itself.")
                    ancestor = (notnull .nodeById(ancestor)).parentId
                }
            }
            let updated = notnull .nodeById(id)
            updated.parentId  = destinationParentId
            updated.name      = name
            updated.changeTime = volumeTimeNow()
            .dirty = true
            .commit()
        }

        mtd freeBytes()->u64
        {
            return .freeBlockCount() * BlockSize
        }

        mtd freeBlockCount()->u64
        {
            var result = 0'u64
            for extent in .free do result += extent.count
            return result
        }

        mtd totalBytes()->u64 => .blockCount * BlockSize
    }
}

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
            failWith(Format.toString("The container must be at least % bytes.", MinimumSize),
                     .InvalidInput)

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
        created              = true
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
        result.deserialize(validHeader.plain.toSlice())
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
        if Core.Crypto.constantTimeEqual(prefix[until HeaderLocatorCheckSize],
                                         locator[until HeaderLocatorCheckSize])
        {
            let plainSize = Crypto.load32(&prefix[HeaderLocatorCheckSize]) ^
                            Crypto.load32(&locator[HeaderLocatorCheckSize])
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
            if !.file.readExactAt(offset + #sizeof(prefix),
                                  record[#sizeof(prefix) until HeaderSlotSize]) do
                return result
            result.plain.resize(LegacyHeaderPlainSize)
            let nonce      = record[0 until Crypto.NonceSize]
            let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + LegacyHeaderPlainSize]
            let tag        = record[Crypto.NonceSize + LegacyHeaderPlainSize until HeaderSlotSize]
            if !Crypto.open(&.keys, HeaderKind, slot, nonce, ciphertext, tag, result.plain.toSlice()) do
                return result
        }

        var reader = ByteReader{result.plain.toSlice()}
        if !reader.matches(HeaderMagic) do
            return result
        let version = reader.readU32()
        if version != LegacyFormatVersion and version != FormatVersion do
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
            var idx      = 0'u64
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

        writer.writeU64(.blocks.free.count)
        for extent in .blocks.free
        {
            writer.writeU64(extent.first)
            writer.writeU64(extent.count)
        }

        return writer.buffer
    }

    mtd deserialize(plain: const [..] u8) fail
    {
        var reader = ByteReader{plain}
        if !reader.matches(HeaderMagic) do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)
        let version = reader.readU32()
        if version != LegacyFormatVersion and version != FormatVersion do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        .sequence = reader.readU64()
        let storedSize = reader.readU64()
        .blockCount = reader.readU64()
        .nextNodeId = reader.readU64()
        .label      = reader.readString(128)
        if storedSize != .containerSize or .blockCount != (.containerSize - DataOffset) / BlockRecordSize do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        let nodeCount = reader.readU64()
        if nodeCount == 0 or nodeCount > 1_000_000 do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)
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
                let logical  = reader.readU64()
                let physical = reader.readU64()
                let count    = reader.readU64()
                if !count or physical >= .blockCount or count > .blockCount - physical or count > .blockCount - totalMappings
                {
                    reader.valid = false
                    break
                }

                node.blocks.reserve(node.blocks.count + count)
                for [i] in count do
                    node.blocks.add({logical + i, physical + i})
                totalMappings += count
            }

            let nodeIndex = .nodes.count
            .nodes.add(#move node)
            if !.nodeLookup.add(&.nodes[nodeIndex], nodeIndex)
            {
                reader.valid = false
                break
            }
        }

        let freeCount = reader.readU64()
        if freeCount > .blockCount do
            reader.valid = false
        else
        {
            .blocks.free.reserve(freeCount)
            for [i] in freeCount
            {
                let first = reader.readU64()
                let count = reader.readU64()
                if !count or first >= .blockCount or count > .blockCount - first
                {
                    reader.valid = false
                    break
                }

                .blocks.free.add({first, count})
            }
        }

        if !reader.valid or .nodeById(1) == null do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)
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
        Crypto.store32(notnull record.buffer + HeaderLocatorCheckSize,
                       cast(u32) @countof(plain) ^
        Crypto.load32(&locator[HeaderLocatorCheckSize]))
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
}

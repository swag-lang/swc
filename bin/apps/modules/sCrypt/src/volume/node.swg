using Core

struct BlockMapping
{
    logical:  u64
    physical: u64
    count:    u64
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
        var low  = 0'u64
        var high = .blocks.count
        while low < high
        {
            let middle = low + (high - low) / 2
            if .blocks[middle].logical + .blocks[middle].count <= logical do
                low = middle + 1
            else do
                high = middle
        }

        return {low < .blocks.count and .blocks[low].logical <= logical, low}
    }

    // Adds one mapping while preserving the canonical coalesced representation.
    mtd appendMapping(mapping: BlockMapping)
    {
        if !mapping.count do
            return
        if .blocks.count
        {
            let previous = .blocks.backPtr()
            if previous.logical + previous.count == mapping.logical and previous.physical + previous.count == mapping.physical
            {
                previous.count += mapping.count
                return
            }
        }
        .blocks.add(mapping)
    }

    // Writes this node into a metadata image or a journal record. Both use the
    // same encoding, so a replayed node and a checkpointed one cannot disagree.
    mtd const serialize(writer: *ByteStream)
    {
        writer.writeLittleEndian(.id)
        writer.writeLittleEndian(.parentId)
        writer.writeSizedString(.name)
        writer.writeLittleEndian(.attributes)
        writer.writeLittleEndian(.size)
        writer.writeLittleEndian(.creationTime)
        writer.writeLittleEndian(.lastAccessTime)
        writer.writeLittleEndian(.lastWriteTime)
        writer.writeLittleEndian(.changeTime)
        writer.writeLittleEndian(cast(u32) .security.count)
        writer.writeBytes(.security.toSlice())

        writer.writeLittleEndian(.blocks.count)
        for mapping in .blocks
        {
            writer.writeLittleEndian(mapping.logical)
            writer.writeLittleEndian(mapping.physical)
            writer.writeLittleEndian(mapping.count)
        }
    }

    // Reads a node written by `serialize`.
    //
    // The plaintext is attacker-controlled once the password is known, so every
    // count that drives an allocation is checked against the container geometry
    // before it is used.
    func deserialize(reader: *ByteStream, blockCount: u64)->Node fail
    {
        var result: retval
        result.id             = reader.readLittleEndian'u64()
        result.parentId       = reader.readLittleEndian'u64()
        result.name           = reader.readSizedString(MaximumNameSize)
        result.attributes     = reader.readLittleEndian'u32()
        result.size           = reader.readLittleEndian'u64()
        result.creationTime   = reader.readLittleEndian'u64()
        result.lastAccessTime = reader.readLittleEndian'u64()
        result.lastWriteTime  = reader.readLittleEndian'u64()
        result.changeTime     = reader.readLittleEndian'u64()

        let securitySize = reader.readLittleEndian'u32()
        if securitySize > MaximumSecuritySize do
            failWith("An entry declares an implausible security descriptor.", .Corrupted)
        result.security.resize(securitySize)
        reader.readBytes(result.security.buffer, securitySize)

        let runCount = reader.readLittleEndian'u64()
        if runCount > blockCount do
            failWith("An entry declares more block runs than the container holds.", .Corrupted)

        var mapped          = 0'u64
        var previousLogical = 0'u64
        for runCount
        {
            let logical  = reader.readLittleEndian'u64()
            let physical = reader.readLittleEndian'u64()
            let count    = reader.readLittleEndian'u64()
            if !count or physical >= blockCount or count > blockCount - physical or count > blockCount - mapped or logical > Swag.U64.Max - count or (result.blocks.count and logical < previousLogical) do
                failWith("A block run falls outside the container.", .Corrupted)

            result.appendMapping({logical, physical, count})
            previousLogical = logical + count
            mapped += count
        }

        if reader.isEof() do
            failWith("The metadata ends inside an entry.", .Corrupted)
        return result
    }
}

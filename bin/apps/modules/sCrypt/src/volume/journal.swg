using Core

// One metadata change, small enough to append instead of rewriting everything.
//
// A change used to cost a full re-serialization of the node table: populating a
// container was quadratic in the number of files. A journal record describes
// only what changed, so a change now costs one small write, and the full
// metadata image is rewritten at a checkpoint instead — every
// `JournalCapacity` records, or when the volume closes.
//
// Records are replayed in sequence order on top of the checkpoint they follow.
// A record that cannot be read stops the replay: everything after it belongs to
// an operation that never completed.
struct JournalRecord
{
    sequence:   u64                     // Position in the single sequence shared with checkpoints.
    nextNodeId: u64
    label:      String
    removed:    Array'u64               // Nodes this change deleted.
    upserted:   Array'Node              // Nodes this change created or modified, in full.
}

impl JournalRecord
{
    // Encodes one change. `upserted` borrows the live nodes, so a record costs
    // no copy of a block map on the way out.
    func encode(sequence, nextNodeId: u64, label: string, removed: const [..] u64, upserted: const [..] *Node)->Array'u8
    {
        var result: retval
        var writer = ByteStream.openWrite(&result)

        writer.writeLittleEndian(sequence)
        writer.writeLittleEndian(nextNodeId)
        writer.writeSizedString(label)

        writer.writeLittleEndian(@countof(removed))
        for id in removed do
            writer.writeLittleEndian(id)

        writer.writeLittleEndian(@countof(upserted))
        for node in upserted do
            node.serialize(&writer)

        return result
    }

    // Decodes one record. Every count is checked against the container geometry
    // before it drives an allocation, because the plaintext is
    // attacker-controlled once the password is known.
    func decode(plain: const [..] u8, blockCount: u64)->JournalRecord fail
    {
        var result: retval
        var reader = ByteStream.openRead(plain)

        result.sequence   = reader.readLittleEndian'u64()
        result.nextNodeId = reader.readLittleEndian'u64()
        result.label      = reader.readSizedString(MaximumLabelSize)

        let removedCount = reader.readLittleEndian'u64()
        if removedCount > MaximumNodeCount do
            failWith("A journal record declares an implausible number of deletions.", .Corrupted)
        result.removed.reserve(removedCount)
        for removedCount do
            result.removed.add(reader.readLittleEndian'u64())

        let upsertCount = reader.readLittleEndian'u64()
        if upsertCount > MaximumNodeCount do
            failWith("A journal record declares an implausible number of entries.", .Corrupted)
        result.upserted.reserve(upsertCount)
        for upsertCount
        {
            let node = try Node.deserialize(&reader, blockCount)
            result.upserted.add(#move node)
        }

        if reader.isEof() do
            failWith("A journal record ends early.", .Corrupted)
        return result
    }
}

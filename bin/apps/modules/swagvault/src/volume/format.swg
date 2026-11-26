using Core

// On-disk layout of a Swag Vault container:
//
//     [ key slots ][ header slot 0 ][ header slot 1 ][ journal ][ block 0 ]...
//
// A key slot holds the master key wrapped by a password-derived key, so a
// password can be changed or revoked without touching anything else.
//
// The two header slots alternate: a checkpoint always writes the slot that is
// not currently active, so a power loss mid-write leaves the previous one
// intact. Between checkpoints, each metadata change appends one small record to
// the circular journal, which is what keeps the cost of a change constant instead
// of a rewrite of the whole metadata blob.
//
// Every record carries its own nonce and authentication tag, and the tag covers
// the record's kind and position, so a record cannot be moved, duplicated, or
// replayed from another offset.

const BlockSize       = 4096_u64
const BlockRecordSize = BlockSize + Crypto.NonceSize + Crypto.TagSize

// The header holds only the volume scalars and the index of the metadata pages,
// so its size does not depend on the number of files.
const HeaderSlotSize         = #command == Swag.CompilerCommand.Test ? 16_u64 * 1024 : 1_u64 * 1024 * 1024
const HeaderLocatorCheckSize = 12_u64
const HeaderRecordPrefixSize = Crypto.RecordLocatorSize + Crypto.NonceSize
const HeaderPlainSize        = HeaderSlotSize - HeaderRecordPrefixSize - Crypto.TagSize
const HeaderSlotCount        = 2_u64

// One journal record covers one metadata change. A change that does not fit
// forces an immediate checkpoint instead, which is the honest fallback rather
// than a variable-size circular buffer.
const JournalRecordSize = 4096_u64
const JournalPlainSize  = JournalRecordSize - HeaderRecordPrefixSize - Crypto.TagSize
const JournalCapacity   = #command == Swag.CompilerCommand.Test ? 16_u64 : 256_u64
const JournalAreaSize   = JournalCapacity * JournalRecordSize

const KeySlotAreaOffset = 0_u64
const HeaderAreaOffset  = KeySlotAreaOffset + KeySlotAreaSize
const JournalAreaOffset = HeaderAreaOffset + HeaderSlotCount * HeaderSlotSize
const DataOffset        = JournalAreaOffset + JournalAreaSize

const MinimumBlocks = 16_u64
const MinimumSize   = DataOffset + MinimumBlocks * BlockRecordSize

// Format version 1 gives the complete slot area one salt and one fixed Argon2id
// cost. Slot records carry no profile selector, and the first occupied slot is
// chosen randomly. Older formats deliberately report the same outcome as a
// wrong password or a damaged container.
const FormatVersion = 1_u32

// Record kinds mixed into every nonce and locator, so a record of one kind can
// never be decrypted as another.
const HeaderKind         = 1_u32
const DataKind           = 2_u32
const HeaderLocatorKind  = 3_u32
const MetadataPageKind   = 5_u32
const JournalKind        = 6_u32
const JournalLocatorKind = 7_u32

// The root directory always exists and always has this identifier.
const RootNodeId = 1_u64

// Size of the buffer used to randomize a new container. Large enough to keep
// the write pattern sequential, small enough to stay off the heap's slow path.
const RandomizeChunkSize = 1_u64 * 1024 * 1024

// The authenticated capacity ends at `containerSize`; the file continues with
// an unrelated random tail. Byte-granular bounds deliberately avoid producing
// another recognizable round size. Tests keep the tail small because they
// create many containers and exercise the same layout contract.
#static if #command == Swag.CompilerCommand.Test
{
    const CamouflageMinimum = 4_u64 * 1024
    const CamouflageMaximum = 16_u64 * 1024
}
else
{
    const CamouflageMinimum = 8_u64 * 1024 * 1024
    const CamouflageMaximum = 2_u64 * 1024 * 1024 * 1024
}

// Upper bounds enforced while parsing metadata. The plaintext is
// attacker-controlled once the password is known, so every count that drives an
// allocation is rejected before it is used.
const MaximumNodeCount    = 100_000_000_u64
const MaximumNameSize     = 4_u64 * 1024
const MaximumLabelSize    = 128_u64
const MaximumSecuritySize = 1_u32 * 1024 * 1024

const HeaderMagic: [16] u8 = [
    0x53, 0x57, 0x41, 0x47, 0x2D, 0x56, 0x41, 0x55,
    0x4C, 0x54, 0x2D, 0x56, 0x31, 0x00, 0x00, 0x00]

// A header slot that was decrypted and passed its magic and version check.
struct HeaderCandidate
{
    valid:    bool     // Whether the slot holds a usable header.
    sequence: u64      // Checkpoint counter; the higher of the two slots wins.
    plain:    Array!{u8}
}

// Reads the fixed prefix of a decrypted header slot from `reader` and returns its
// checkpoint counter. Failing here means the slot is unusable, not that the
// password is wrong: the caller decides how to report it.
func readHeaderPrefix(reader: *ByteStream)->u64 fail
{
    var magic: [#sizeof(HeaderMagic)] u8
    try reader.readBytes(&magic[0], #sizeof(magic))
    if Swag.memcmp(&magic[0], &HeaderMagic[0], #sizeof(magic)) != 0
    {
        fail volumeError(.Corrupted)
    }

    let version = try reader.readLittleEndian!{u32}()
    if version != FormatVersion
    {
        fail volumeError(.Corrupted)
    }

    return try reader.readLittleEndian!{u64}()
}

// Returns the checkpoint counter of a decrypted header slot, see [[readHeaderPrefix]].
func parseHeaderSequence(plain: const [..] u8)->u64 fail
{
    var reader = ByteStream.openRead(plain)
    return try readHeaderPrefix(&reader)
}

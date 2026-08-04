using Core

// On-disk layout of an sCrypt container:
//
//     [ salt ][ header slot 0 ][ header slot 1 ][ block 0 ][ block 1 ]...
//
// The two header slots alternate: a commit always writes the slot that is not
// currently active, so a power loss mid-write leaves the previous one intact.
// Every block record carries its own nonce and authentication tag, so a block
// cannot be moved, duplicated, or replayed from another offset.

const BlockSize              = 4096'u64
const BlockRecordSize        = BlockSize + Crypto.NonceSize + Crypto.TagSize
const HeaderSlotSize         = #command == Swag.CompilerCommand.Test ? 256'u64 * 1024 : 8'u64 * 1024 * 1024
const LegacyHeaderPlainSize  = HeaderSlotSize - Crypto.NonceSize - Crypto.TagSize
const HeaderLocatorCheckSize = 12'u64
const HeaderRecordPrefixSize = Crypto.RecordLocatorSize + Crypto.NonceSize
const HeaderPlainSize        = HeaderSlotSize - HeaderRecordPrefixSize - Crypto.TagSize
const HeaderSlotCount        = 2'u64
const DataOffset             = Crypto.SaltSize + HeaderSlotCount * HeaderSlotSize
const MinimumBlocks          = 16'u64
const MinimumSize            = DataOffset + MinimumBlocks * BlockRecordSize
const LegacyFormatVersion    = 1'u32
const FormatVersion          = 2'u32

// Record kinds mixed into every nonce and locator, so a header can never be
// decrypted as a data block and vice versa.
const HeaderKind        = 1'u32
const DataKind          = 2'u32
const HeaderLocatorKind = 3'u32

// The root directory always exists and always has this identifier.
const RootNodeId = 1'u64

// Size of the buffer used to randomize a new container. Large enough to keep
// the write pattern sequential, small enough to stay off the heap's slow path.
const RandomizeChunkSize = 1'u64 * 1024 * 1024

// Upper bounds enforced while parsing a header. The plaintext is
// attacker-controlled once the password is known, so every count that drives an
// allocation is rejected before it is used.
const MaximumNodeCount    = 1_000_000'u64
const MaximumNameSize     = 4'u64 * 1024
const MaximumLabelSize    = 128'u64
const MaximumSecuritySize = 1'u32 * 1024 * 1024

const HeaderMagic: [16] u8 = [
    0x73, 0x43, 0x72, 0x79, 0x70, 0x74, 0x2D, 0x56,
    0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x2D, 0x31, 0x00]

// A header slot that was decrypted and passed its magic and version check.
struct HeaderCandidate
{
    valid:    bool     // Whether the slot holds a usable header.
    sequence: u64      // Commit counter; the higher of the two slots wins.
    plain:    Array'u8
}

// Reads the fixed prefix of a decrypted header slot and returns its commit
// counter. Failing here means the slot is unusable, not that the password is
// wrong: the caller decides how to report it.
func parseHeaderSequence(plain: const [..] u8)->u64 fail
{
    var reader = ByteStream.openRead(plain)

    var magic: [#sizeof(HeaderMagic)] u8
    reader.readBytes(&magic[0], #sizeof(magic))
    if @memcmp(&magic[0], &HeaderMagic[0], #sizeof(magic)) != 0 do
        failWith("The container does not start with an sCrypt header.", .Corrupted)

    let version = reader.readLittleEndian'u32()
    if version != LegacyFormatVersion and version != FormatVersion do
        failWith("The container format version is not supported.", .Corrupted)

    return reader.readLittleEndian'u64()
}

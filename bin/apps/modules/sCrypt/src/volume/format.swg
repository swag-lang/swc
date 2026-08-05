using Core

// On-disk layout of an sCrypt container:
//
//     [ key slots ][ header slot 0 ][ header slot 1 ][ journal ][ block 0 ]...
//
// A key slot holds the master key wrapped by a password-derived key, so a
// password can be changed or revoked without touching anything else.
//
// The two header slots alternate: a checkpoint always writes the slot that is
// not currently active, so a power loss mid-write leaves the previous one
// intact. Between checkpoints, each metadata change appends one small record to
// the circular journal, which is what keeps a change O(1) instead of a rewrite
// of the whole metadata blob.
//
// Every record carries its own nonce and authentication tag, and the tag covers
// the record's kind and position, so a record cannot be moved, duplicated, or
// replayed from another offset.

const BlockSize       = 4096'u64
const BlockRecordSize = BlockSize + Crypto.NonceSize + Crypto.TagSize

// The header now holds only the volume scalars and the index of the metadata
// pages, so it no longer has to grow with the number of files.
const HeaderSlotSize         = #command == Swag.CompilerCommand.Test ? 64'u64 * 1024 : 1'u64 * 1024 * 1024
const HeaderLocatorCheckSize = 12'u64
const HeaderRecordPrefixSize = Crypto.RecordLocatorSize + Crypto.NonceSize
const HeaderPlainSize        = HeaderSlotSize - HeaderRecordPrefixSize - Crypto.TagSize
const HeaderSlotCount        = 2'u64

// One journal record covers one metadata change. A change that does not fit
// forces an immediate checkpoint instead, which is the honest fallback rather
// than a variable-size circular buffer.
const JournalRecordSize  = 4096'u64
const JournalPlainSize   = JournalRecordSize - HeaderRecordPrefixSize - Crypto.TagSize
const JournalCapacity    = #command == Swag.CompilerCommand.Test ? 16'u64 : 256'u64
const JournalAreaSize    = JournalCapacity * JournalRecordSize

const KeySlotAreaOffset = 0'u64
const HeaderAreaOffset  = KeySlotAreaOffset + KeySlotAreaSize
const JournalAreaOffset = HeaderAreaOffset + HeaderSlotCount * HeaderSlotSize
const DataOffset        = JournalAreaOffset + JournalAreaSize

const MinimumBlocks = 16'u64
const MinimumSize   = DataOffset + MinimumBlocks * BlockRecordSize

// Format version 3 replaced the password-derived encryption key with a master
// key and key slots, PBKDF2-HMAC-SHA-256 with Argon2id, and the two-pass
// encrypt-then-MAC record with a single-pass AEAD. None of those can be read
// with the previous key schedule, so an older container reports the same
// outcome as a wrong password, deliberately: a caller must never be able to
// tell one from the other.
const FormatVersion = 3'u32

// Record kinds mixed into every nonce and locator, so a record of one kind can
// never be decrypted as another.
const HeaderKind        = 1'u32
const DataKind          = 2'u32
const HeaderLocatorKind = 3'u32
const MetadataPageKind  = 5'u32
const JournalKind       = 6'u32
const JournalLocatorKind = 7'u32

// The root directory always exists and always has this identifier.
const RootNodeId = 1'u64

// Size of the buffer used to randomize a new container. Large enough to keep
// the write pattern sequential, small enough to stay off the heap's slow path.
const RandomizeChunkSize = 1'u64 * 1024 * 1024

// Upper bounds enforced while parsing metadata. The plaintext is
// attacker-controlled once the password is known, so every count that drives an
// allocation is rejected before it is used.
const MaximumNodeCount    = 100_000_000'u64
const MaximumNameSize     = 4'u64 * 1024
const MaximumLabelSize    = 128'u64
const MaximumSecuritySize = 1'u32 * 1024 * 1024

const HeaderMagic: [16] u8 = [
    0x73, 0x43, 0x72, 0x79, 0x70, 0x74, 0x2D, 0x56,
    0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x2D, 0x33, 0x00]

// A header slot that was decrypted and passed its magic and version check.
struct HeaderCandidate
{
    valid:    bool     // Whether the slot holds a usable header.
    sequence: u64      // Checkpoint counter; the higher of the two slots wins.
    plain:    Array'u8
}

// Reads the fixed prefix of a decrypted header slot and returns its checkpoint
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
    if version != FormatVersion do
        failWith("The container format version is not supported.", .Corrupted)

    return reader.readLittleEndian'u64()
}

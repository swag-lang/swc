using Core

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
const HeaderKind             = 1'u32
const DataKind               = 2'u32
const HeaderLocatorKind      = 3'u32

const HeaderMagic: [16] u8 = [
    0x73, 0x43, 0x72, 0x79, 0x70, 0x74, 0x2D, 0x56,
    0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x2D, 0x31, 0x00]

struct HeaderCandidate
{
    valid:    bool
    sequence: u64
    plain:    Array'u8
}

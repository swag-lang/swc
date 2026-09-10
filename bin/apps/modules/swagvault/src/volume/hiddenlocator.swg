using Core

// Each version-1 key slot has 132 unused trailing bytes. Reserve its last 128 bytes for
// an independently authenticated hidden-volume locator. Ordinary password rotation preserves
// this padding even when no hidden volume exists; no outer flag advertises its presence.
const HiddenLocatorSize    = 128'u64
const HiddenLocatorKind    = 9'u32
const HiddenGeometrySize   = 16'u64
const HiddenNonceOffset    = cast(u64) Crypto.SaltSize
const HiddenGeometryOffset = HiddenNonceOffset + Crypto.NonceSize
const HiddenTagOffset      = HiddenGeometryOffset + HiddenGeometrySize
const HiddenPayloadEnd     = HiddenTagOffset + Crypto.TagSize
#assert(HiddenPayloadEnd <= HiddenLocatorSize)
#assert(KeySlotPrefixSize + KeySlotPlainSize <= KeySlotSize - HiddenLocatorSize)

struct HiddenLocator {}

impl HiddenLocator
{
    func offset(index: u64)->u64 => (index + 1) * KeySlotSize - HiddenLocatorSize

    func opensOuter(stream: *File.FileStream, password: const [..] u8)->bool fail
    {
        var area: [KeySlotAreaSize] u8
        if not stream.readExactAt(0, area) do
            failWith("The container is truncated or unreadable.", .Io)
        var key = try Crypto.deriveSlotKey(password, area[until Crypto.SaltSize])
        defer Core.Crypto.secureClear(key)
        var master: [Crypto.MasterKeySize] u8
        defer Core.Crypto.secureClear(master)
        for index in KeySlotCount
        {
            var slot = KeySlot.decode(area[keySlotPayloadOffset(index) until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(key, index, master) do
                return true
        }

        return false
    }

    // A locator authenticates the complete hidden view before any offset is followed.
    func find(stream: *File.FileStream, password: const [..] u8)->FreeExtent fail
    {
        let hostSize = try stream.size()
        for index in KeySlotCount
        {
            var record: [HiddenLocatorSize] u8
            if not stream.readExactAt(offset(index), record) do
                break
            let salt   = record[until Crypto.SaltSize]
            let nonce  = record[HiddenNonceOffset until HiddenGeometryOffset]
            let cipher = record[HiddenGeometryOffset until HiddenTagOffset]
            let tag    = record[HiddenTagOffset until HiddenPayloadEnd]
            var key    = try Crypto.deriveSlotKey(password, salt)
            defer Core.Crypto.secureClear(key)
            var plain: [HiddenGeometrySize] u8
            defer Core.Crypto.secureClear(plain)
            if not (try Core.Crypto.chacha20Poly1305Open(key, nonce, cipher, tag, Crypto.associatedData(HiddenLocatorKind, index), plain)) do
                continue
            var reader = ByteStream.openRead(plain)
            let first  = reader.readLittleEndian'u64()
            let count  = reader.readLittleEndian'u64()
            if first < DataOffset or first > hostSize or count < MinimumSize or count > hostSize - first do
                break
            return {first, count}
        }

        failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)
        unreachable
    }

    // Publish only after the hidden key slot and checkpoint are durable.
    func write(stream: *File.FileStream, index: u64, password: const [..] u8, region: FreeExtent) fail
    {
        var record: [HiddenLocatorSize] u8
        Core.Crypto.randomBytes(record)
        var plain: Array'u8
        defer Core.Crypto.secureClear(plain.toSlice())
        var writer = ByteStream.openWrite(&plain)
        writer.writeLittleEndian(region.first)
        writer.writeLittleEndian(region.count)
        var key = try Crypto.deriveSlotKey(password, record[until Crypto.SaltSize])
        defer Core.Crypto.secureClear(key)
        try Core.Crypto.chacha20Poly1305Seal(key, record[HiddenNonceOffset until HiddenGeometryOffset], plain.toSlice(), Crypto.associatedData(HiddenLocatorKind, index), record[HiddenGeometryOffset until HiddenTagOffset], record[HiddenTagOffset until HiddenPayloadEnd])
        stream.writeAllAt(offset(index), record)
        stream.flush()
    }

    func erase(stream: *File.FileStream, index: u64) fail
    {
        var record: [HiddenLocatorSize] u8
        Core.Crypto.randomBytes(record)
        stream.writeAllAt(offset(index), record)
        stream.flush()
    }
}

using Core

// Each version-1 key slot has 132 unused trailing bytes. Its last 128 bytes are reserved for
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

// The sealed record, hidden in the tail of a key slot, that tells a hidden-volume password where
// its volume lives inside the outer container.
struct HiddenLocator {}

impl HiddenLocator
{
    // Returns the offset of the locator in the key slot at `index`.
    func offset(index: u64)->u64 => (index + 1) * KeySlotSize - HiddenLocatorSize

    // Returns whether `password` unwraps one of the outer container's key slots.
    func opensOuter(stream: *File.FileStream, password: const [..] u8)->bool fail
    {
        var area: [KeySlotAreaSize] u8
        if not (try stream.readExactAt(0, area)) do
            try failWith("The container is truncated or unreadable.", .Io)
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

    // Returns the hidden region `password` opens.
    //
    // A locator authenticates the complete hidden view before any offset is followed. Fails with
    // [[ErrorKind.PasswordOrDamaged]] when no locator opens under `password`.
    func find(stream: *File.FileStream, password: const [..] u8)->FreeExtent fail
    {
        let hostSize = try stream.size()
        for index in KeySlotCount
        {
            var record: [HiddenLocatorSize] u8
            if not (try stream.readExactAt(offset(index), record)) do
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
            let first  = try reader.readLittleEndian'u64()
            let count  = try reader.readLittleEndian'u64()
            if first < DataOffset or first > hostSize or count < MinimumSize or count > hostSize - first do
                break
            return {first, count}
        }

        try failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)
        unreachable
    }

    // Seals `region` into the locator of the key slot at `index`, under a key `password` derives.
    //
    // Call it only once the hidden key slot and checkpoint are durable.
    func write(stream: *File.FileStream, index: u64, password: const [..] u8, region: FreeExtent) fail
    {
        var record: [HiddenLocatorSize] u8
        try Core.Crypto.randomBytes(record)
        var plain: Array'u8
        defer Core.Crypto.secureClear(plain.toSlice())
        var writer = ByteStream.openWrite(&plain)
        writer.writeLittleEndian(region.first)
        writer.writeLittleEndian(region.count)
        var key = try Crypto.deriveSlotKey(password, record[until Crypto.SaltSize])
        defer Core.Crypto.secureClear(key)
        try Core.Crypto.chacha20Poly1305Seal(key, record[HiddenNonceOffset until HiddenGeometryOffset], plain.toSlice(), Crypto.associatedData(HiddenLocatorKind, index), record[HiddenGeometryOffset until HiddenTagOffset], record[HiddenTagOffset until HiddenPayloadEnd])
        try stream.writeAllAt(offset(index), record)
        try stream.flush()
    }

    // Overwrites the locator of the key slot at `index` with random bytes.
    func erase(stream: *File.FileStream, index: u64) fail
    {
        var record: [HiddenLocatorSize] u8
        try Core.Crypto.randomBytes(record)
        try stream.writeAllAt(offset(index), record)
        try stream.flush()
    }
}

using Core

// One key slot: an independent way to unwrap the same master key.
//
// The encryption keys are derived from a random master key, never from a
// password. A password only ever unwraps that master key, which is what makes
// changing a password a hundred-byte write instead of a rewrite of the whole
// container, and what allows several passwords to coexist.
//
// One random salt at the start of the slot area feeds every password derivation.
// A password therefore costs one Argon2id call and can try every slot with cheap
// authenticated opens. Each slot keeps a random prefix at the same position as
// that salt, so the area carries no structural distinction.
struct KeySlot
{
    nonce:   [Crypto.NonceSize] u8
    wrapped: [Crypto.MasterKeySize] u8     // The master key, sealed by the container-wide password key.
    tag:     [Crypto.TagSize] u8
}

const KeySlotPlainSize = Crypto.NonceSize + Crypto.MasterKeySize + Crypto.TagSize

// Slots use a fixed width so the headers and every data block stay
// at the same physical offset. The first 32 bytes of each record are random;
// in slot zero those bytes are the container-wide salt.
const KeySlotSize        = 256'u64
const KeySlotCount       = 4'u64
const KeySlotAreaSize    = KeySlotCount * KeySlotSize
const KeySlotPrefixSize  = cast(u64) Crypto.SaltSize
const KeySlotPayloadSize = KeySlotSize - KeySlotPrefixSize

#assert(KeySlotCount == 4)

// Record kind mixed into the nonce and the associated data of a wrapped key.
const KeySlotKind = 8'u32

// Bit that marks the slot at `index` as holding a password, in the mask the
// volume header carries.
func keySlotBit(index: u64)->u32 => cast(u32) (1'u64 << index)

// The byte range one slot owns after its uniformly random prefix.
func keySlotPayloadOffset(index: u64)->u64 => KeySlotAreaOffset + index * KeySlotSize + KeySlotPrefixSize

// Maps a uniformly random word onto the four physical slots without bias.
func keySlotIndex(random: u64)->u64 => random & (KeySlotCount - 1)

func randomKeySlotIndex()->u64 fail
{
    var random: u64
    Core.Crypto.randomBytes(@mkslice(cast([*] u8) &random, #sizeof(random)))
    return keySlotIndex(random)
}

impl KeySlot
{
    // Builds a slot that unwraps `master` with the container-wide password key.
    func create(slotKey, master: const [..] u8, index: u64)->KeySlot fail
    {
        Debug.assert(@countof(slotKey) == Crypto.KeySize)
        Debug.assert(@countof(master) == Crypto.MasterKeySize)

        var result: retval
        Core.Crypto.randomBytes(result.nonce)
        try Core.Crypto.chacha20Poly1305Seal(slotKey, result.nonce, master, Crypto.associatedData(KeySlotKind, index), result.wrapped, result.tag)
        return result
    }

    // Unwraps the master key into `master`, reporting whether this slot belongs
    // to the already-derived password key.
    mtd const unwrap(slotKey: const [..] u8, index: u64, master: [..] u8)->bool fail
    {
        Debug.assert(@countof(slotKey) == Crypto.KeySize)
        Debug.assert(@countof(master) == Crypto.MasterKeySize)
        return Core.Crypto.chacha20Poly1305Open(slotKey, .nonce, .wrapped, .tag, Crypto.associatedData(KeySlotKind, index), master)
    }

    // Serializes the authenticated payload after the slot's random prefix.
    mtd const encode()->[KeySlotPayloadSize] u8 fail
    {
        var result: retval
        Core.Crypto.randomBytes(result)

        var offset = 0'u64
        @memcpy(&result[offset], &.nonce[0], Crypto.NonceSize)
        offset += Crypto.NonceSize
        @memcpy(&result[offset], &.wrapped[0], Crypto.MasterKeySize)
        offset += Crypto.MasterKeySize
        @memcpy(&result[offset], &.tag[0], Crypto.TagSize)
        return result
    }

    // Rebuilds a slot from its on-disk payload. Any byte pattern decodes: an
    // unused slot simply fails to unwrap.
    func decode(record: const [..] u8)->KeySlot
    {
        Debug.assert(@countof(record) == KeySlotPayloadSize)

        var result: retval
        var offset = 0'u64
        @memcpy(&result.nonce[0], @dataof(record) + offset, Crypto.NonceSize)
        offset += Crypto.NonceSize
        @memcpy(&result.wrapped[0], @dataof(record) + offset, Crypto.MasterKeySize)
        offset += Crypto.MasterKeySize
        @memcpy(&result.tag[0], @dataof(record) + offset, Crypto.TagSize)
        return result
    }

    mtd clear()
    {
        Core.Crypto.secureClear(.wrapped)
        Core.Crypto.secureClear(.nonce)
    }
}

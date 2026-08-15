using Core

// One key slot: an independent way to unwrap the same master key.
//
// The encryption keys are derived from a random master key, never from a
// password. A password only ever unwraps that master key, which is what makes
// changing a password a hundred-byte write instead of a rewrite of the whole
// container, and what allows several passwords to coexist.
//
// On disk a slot is `KeySlotSize` bytes and every one of them is uniformly
// distributed: the salt, the mask and the nonce are random, the wrapped key and
// its tag are ciphertext, and the padding is random. An unused slot is
// indistinguishable from a used one, so the container never reveals how many
// passwords open it.
struct KeySlot
{
    salt:    [Crypto.SaltSize] u8
    mask:    u8     // One-time pad for the profile byte, so the slot area carries no readable structure.
    profile: u8     // Cost profile, masked. Its value modulo the profile count selects the profile.
    nonce:   [Crypto.NonceSize] u8
    wrapped: [Crypto.MasterKeySize] u8     // The master key, sealed by the key derived from this slot's password.
    tag:     [Crypto.TagSize] u8
}

const KeySlotPlainSize = Crypto.SaltSize + 2 + Crypto.NonceSize + Crypto.MasterKeySize + Crypto.TagSize

// Slots are padded so the area keeps a round shape and gains room for a future
// field without moving the header.
const KeySlotSize     = 256'u64
const KeySlotCount    = 4'u64
const KeySlotAreaSize = KeySlotCount * KeySlotSize

// Record kind mixed into the nonce and the associated data of a wrapped key.
const KeySlotKind = 4'u32

private const Argon2ProfileCountByte = cast(u8) Crypto.Argon2ProfileCount

// Bit that marks the slot at `index` as holding a password, in the mask the
// volume header carries.
func keySlotBit(index: u64)->u32 => cast(u32) (1'u64 << index)

impl KeySlot
{
    // Builds a slot that unwraps `master` for `password` at `profile`.
    //
    // The whole slot is filled with random bytes first, so the padding carries
    // no structure and the salt and nonce are fresh for every slot ever written.
    func create(password: const [..] u8, master: const [..] u8, profile: Crypto.Argon2Profile, index: u64)->KeySlot fail
    {
        Debug.assert(@countof(master) == Crypto.MasterKeySize)

        var result: retval
        Core.Crypto.randomBytes(result.salt)
        Core.Crypto.randomBytes(@mkslice(cast([*] u8) &result.mask, 1))

        // Any byte congruent to the profile modulo the profile count names that
        // profile, and the mask makes the stored byte uniform.
        var spread: [1] u8
        Core.Crypto.randomBytes(spread)
        let raw = cast(u8) ((spread[0] - (spread[0] % Argon2ProfileCountByte)) + cast(u8) profile)
        result.profile = raw ^ result.mask

        var slotKey = try Crypto.deriveSlotKey(password, result.salt, profile)
        defer Core.Crypto.secureClear(slotKey)

        Core.Crypto.randomBytes(result.nonce)
        try Core.Crypto.chacha20Poly1305Seal(slotKey, result.nonce, master, Crypto.associatedData(KeySlotKind, index), result.wrapped, result.tag)
        return result
    }

    // The profile this slot was written with.
    mtd const profileValue()->Crypto.Argon2Profile
    {
        return cast(Crypto.Argon2Profile) ((.profile ^ .mask) % Argon2ProfileCountByte)
    }

    // Unwraps the master key into `master`, reporting whether this slot belongs
    // to `password`.
    //
    // Every slot costs one full Argon2id derivation whether or not it holds a
    // password, which is deliberate: a caller cannot learn which slots are in
    // use by timing them.
    mtd const unwrap(password: const [..] u8, index: u64, master: [..] u8)->bool fail
    {
        Debug.assert(@countof(master) == Crypto.MasterKeySize)

        var slotKey = try Crypto.deriveSlotKey(password, .salt, .profileValue())
        defer Core.Crypto.secureClear(slotKey)
        return Core.Crypto.chacha20Poly1305Open(slotKey, .nonce, .wrapped, .tag, Crypto.associatedData(KeySlotKind, index), master)
    }

    // Serializes the slot into a full `KeySlotSize` record, padded with random
    // bytes so no two writes of the same slot look alike.
    mtd const encode()->[KeySlotSize] u8 fail
    {
        var result: retval
        Core.Crypto.randomBytes(result)

        var offset = 0'u64
        @memcpy(&result[offset], &.salt[0], Crypto.SaltSize)
        offset         += Crypto.SaltSize
        result[offset] = .mask
        offset         += 1
        result[offset] = .profile
        offset         += 1
        @memcpy(&result[offset], &.nonce[0], Crypto.NonceSize)
        offset += Crypto.NonceSize
        @memcpy(&result[offset], &.wrapped[0], Crypto.MasterKeySize)
        offset += Crypto.MasterKeySize
        @memcpy(&result[offset], &.tag[0], Crypto.TagSize)
        return result
    }

    // Rebuilds a slot from its on-disk record. Any byte pattern decodes: an
    // unused slot simply fails to unwrap.
    func decode(record: const [..] u8)->KeySlot
    {
        Debug.assert(@countof(record) == KeySlotSize)

        var result: retval
        var offset = 0'u64
        @memcpy(&result.salt[0], @dataof(record) + offset, Crypto.SaltSize)
        offset         += Crypto.SaltSize
        result.mask    = record[offset]
        offset         += 1
        result.profile = record[offset]
        offset         += 1
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
        Core.Crypto.secureClear(.salt)
        Core.Crypto.secureClear(.nonce)
    }
}

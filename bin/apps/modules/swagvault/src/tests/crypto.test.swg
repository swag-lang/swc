#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func sameCryptoBytes(left, right: const [..] u8)->bool
{
    return left.count == right.count and
           Swag.memcmp(left.buffer, right.buffer, left.count) == 0
}

func testMasterKey(seed: u8)->[Crypto.MasterKeySize] u8
{
    var result: retval
    for i in Crypto.MasterKeySize do
        result[i] = cast(u8) ((i * 7 + seed) & 0xFF)
    return result
}

#test
{
    // A record is bound to its key, its kind, and its position, so it cannot be
    // moved, duplicated, or replayed from another offset.
    let master = testMasterKey(1)
    var keys   = expect Crypto.deriveKeys(master)

    let plain:  [6] u8 = [1, 2, 3, 4, 5, 6]
    var nonce:  [Crypto.NonceSize] u8
    var cipher: [6] u8
    var tag:    [Crypto.TagSize] u8
    expect Crypto.seal(&keys, 7, 11, plain, nonce, cipher, tag)
    Swag.assert(!sameCryptoBytes(cipher, plain))

    var opened: [6] u8
    Swag.assert(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened))
    Swag.assert(sameCryptoBytes(opened, plain))

    cipher[0] ^= 1
    Swag.assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    cipher[0]               ^= 1
    tag[Crypto.TagSize - 1] ^= 1
    Swag.assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    tag[Crypto.TagSize - 1] ^= 1
    nonce[0]                ^= 1
    Swag.assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    nonce[0] ^= 1
    Swag.assert(!(expect Crypto.open(&keys, 8, 11, nonce, cipher, tag, opened)))
    Swag.assert(!(expect Crypto.open(&keys, 7, 12, nonce, cipher, tag, opened)))

    // Another master key never opens the same record.
    var otherKeys = expect Crypto.deriveKeys(testMasterKey(2))
    Swag.assert(!(expect Crypto.open(&otherKeys, 7, 11, nonce, cipher, tag, opened)))

    var shortNonce: [Crypto.NonceSize - 1] u8
    Swag.assert(!(expect Crypto.open(&keys, 7, 11, shortNonce, cipher, tag, opened)))

    keys.clear()
    for byte in keys.record do
        Swag.assert(byte == 0)
    for byte in keys.locator do
        Swag.assert(byte == 0)
    otherKeys.clear()
}

#test
{
    // The record key and the locator key are derived from the same master key
    // but are unrelated, and each one is reproducible.
    let master = testMasterKey(3)
    var first  = expect Crypto.deriveKeys(master)
    var second = expect Crypto.deriveKeys(master)
    Swag.assert(sameCryptoBytes(first.record, second.record))
    Swag.assert(sameCryptoBytes(first.locator, second.locator))
    Swag.assert(!sameCryptoBytes(first.record, first.locator))

    var different = expect Crypto.deriveKeys(testMasterKey(4))
    Swag.assert(!sameCryptoBytes(first.record, different.record))
    Swag.assert(!sameCryptoBytes(first.locator, different.locator))

    let locator = expect Crypto.recordLocator(first.locator, 3, 0)
    Swag.assert(sameCryptoBytes(locator, expect Crypto.recordLocator(first.locator, 3, 0)))
    Swag.assert(!sameCryptoBytes(locator, expect Crypto.recordLocator(first.locator, 3, 1)))
    Swag.assert(!sameCryptoBytes(locator, expect Crypto.recordLocator(first.locator, 4, 0)))
    Swag.assert(!sameCryptoBytes(locator, expect Crypto.recordLocator(first.record, 3, 0)))

    first.clear()
    second.clear()
    different.clear()
}

#test
{
    // A key slot wraps the master key under the key derived once for the whole
    // slot area. Wrapped bytes never repeat because each slot draws a fresh nonce.
    let master                     = testMasterKey(5)
    let password                   = Swag.makeSlice(cast(const [*] u8) ("slot password").buffer, 13)
    let wrongPassword              = Swag.makeSlice(cast(const [*] u8) ("slot passwore").buffer, 13)
    let salt: [Crypto.SaltSize] u8 = [11]
    var slotKey                    = expect Crypto.deriveSlotKey(password, salt)
    var wrongSlotKey               = expect Crypto.deriveSlotKey(wrongPassword, salt)

    var slot  = expect KeySlot.create(slotKey, master, 0)
    var other = expect KeySlot.create(slotKey, master, 0)
    Swag.assert(!sameCryptoBytes(slot.wrapped, other.wrapped))

    var unwrapped: [Crypto.MasterKeySize] u8
    Swag.assert(expect slot.unwrap(slotKey, 0, unwrapped))
    Swag.assert(sameCryptoBytes(unwrapped, master))

    // The slot index is bound into the record, so a slot cannot be copied to
    // another position.
    Swag.assert(!(expect slot.unwrap(slotKey, 1, unwrapped)))

    Swag.assert(!(expect slot.unwrap(wrongSlotKey, 0, unwrapped)))

    // A slot survives a round trip through its on-disk record, padding included.
    let record = expect slot.encode()
    Swag.assert(record.count == KeySlotPayloadSize)
    var decoded = KeySlot.decode(record)
    Swag.assert(expect decoded.unwrap(slotKey, 0, unwrapped))
    Swag.assert(sameCryptoBytes(unwrapped, master))

    // Two encodings of the same slot differ only in their random padding.
    let again = expect slot.encode()
    Swag.assert(!sameCryptoBytes(record, again))
    Swag.assert(sameCryptoBytes(record[0 until KeySlotPlainSize], again[0 until KeySlotPlainSize]))

    // Pure noise decodes without failing and simply does not unwrap, which is
    // what makes an unused slot indistinguishable from a used one.
    var noise: [KeySlotPayloadSize] u8
    expect Core.Crypto.randomBytes(noise)
    var fromNoise = KeySlot.decode(noise)
    Swag.assert(!(expect fromNoise.unwrap(slotKey, 0, unwrapped)))

    slot.clear()
    other.clear()
    decoded.clear()
    fromNoise.clear()
    Core.Crypto.secureClear(slotKey)
    Core.Crypto.secureClear(wrongSlotKey)
    Core.Crypto.secureClear(unwrapped)
}

#test
{
    // Version 1 uses one fixed KDF profile. Derivation is reproducible and both
    // the password and the common salt contribute to the resulting key.
    let password                            = Swag.makeSlice(cast(const [*] u8) ("profiles").buffer, 8)
    let differentPassword                   = Swag.makeSlice(cast(const [*] u8) ("profilet").buffer, 8)
    let salt:          [Crypto.SaltSize] u8 = [17]
    let differentSalt: [Crypto.SaltSize] u8 = [18]

    var first             = expect Crypto.deriveSlotKey(password, salt)
    var second            = expect Crypto.deriveSlotKey(password, salt)
    var withOtherPassword = expect Crypto.deriveSlotKey(differentPassword, salt)
    var withOtherSalt     = expect Crypto.deriveSlotKey(password, differentSalt)
    Swag.assert(sameCryptoBytes(first, second))
    Swag.assert(!sameCryptoBytes(first, withOtherPassword))
    Swag.assert(!sameCryptoBytes(first, withOtherSalt))
    Core.Crypto.secureClear(first)
    Core.Crypto.secureClear(second)
    Core.Crypto.secureClear(withOtherPassword)
    Core.Crypto.secureClear(withOtherSalt)
}

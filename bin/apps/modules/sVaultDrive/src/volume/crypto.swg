using Core

namespace Crypto
{
    const SaltSize          = 32
    const NonceSize         = Core.Crypto.ChaCha20Poly1305NonceSize
    const TagSize           = Core.Crypto.ChaCha20Poly1305TagSize
    const KeySize           = Core.Crypto.ChaCha20Poly1305KeySize
    const MasterKeySize     = 64
    const RecordLocatorSize = 16

    // Domain separators folded into the master key. Two keys derived for
    // different purposes are unrelated, so a weakness in one cannot be carried
    // into the other.
    // These published domain separators retain the former product spelling so existing
    // containers derive the same keys after the application rename.
    const RecordKeyContext  = "sCrypt record key v3"
    const LocatorKeyContext = "sCrypt locator key v3"

    // A test build derives keys with a token cost. Nothing a test writes is
    // meant to survive, and a real profile would dominate every test run.
    #[Swag.NoDoc]
    const TestProfile = #command == Swag.CompilerCommand.Test

    // The master key protects everything else; a slot key only ever unwraps it.
    struct Keys
    {
        record:  [KeySize] u8     // Seals metadata records and data blocks.
        locator: [KeySize] u8     // Derives the record locators that hide the container's structure.
    }

    impl Keys
    {
        mtd clear()
        {
            Core.Crypto.secureClear(.record)
            Core.Crypto.secureClear(.locator)
        }
    }

    // Version 4 gives every password in a container the same fixed cost. The
    // slot area therefore carries no profile selector, authenticated or not;
    // changing the cost is a format-version change.
    func slotParameters()->Core.Crypto.Argon2Parameters
    {
        #static if TestProfile do
            return {memoryKib: 32, iterations: 1, parallelism: 1}
        return {memoryKib: 256 * 1024, iterations: 3, parallelism: 4}
    }

    // Derives the key that unwraps one key slot's copy of the master key.
    //
    // This is the only place a password is turned into key material, and it is
    // deliberately expensive: Argon2id costs an attacker memory, which is what
    // PBKDF2 never did.
    func deriveSlotKey(password, salt: const [..] u8)->[KeySize] u8 fail
    {
        var result: retval
        try Core.Crypto.argon2id(password, salt, slotParameters(), result)
        return result
    }

    // Expands the master key into the keys the container actually uses.
    func deriveKeys(master: const [..] u8)->Keys fail
    {
        var result: retval
        try Core.Hash.Blake2b.computeKeyed(master, RecordKeyContext, result.record)
        try Core.Hash.Blake2b.computeKeyed(master, LocatorKeyContext, result.locator)
        return result
    }

    #[Swag.Inline]
    func low32(value: u64)->u32 => cast(u32) (value & 0xFFFF_FFFF)

    #[Swag.Inline]
    func store32(data: [*] u8, value: u32)
    {
        data[0] = cast(u8) (value & 0xFF)
        data[1] = cast(u8) ((value >> 8) & 0xFF)
        data[2] = cast(u8) ((value >> 16) & 0xFF)
        data[3] = cast(u8) ((value >> 24) & 0xFF)
    }

    #[Swag.Inline]
    func load32(data: const [*] u8)->u32
    {
        return cast(u32) data[0] | (cast(u32) data[1] << 8) |
               (cast(u32) data[2] << 16) | (cast(u32) data[3] << 24)
    }

    // Binds a record to its kind and its position. A block cannot be moved,
    // duplicated, or replayed from another offset, because the tag covers both.
    func associatedData(kind: u32, recordId: u64)->[12] u8
    {
        var result: retval
        store32(&result[0], kind)
        store32(&result[4], low32(recordId))
        store32(&result[8], low32(recordId >> 32))
        return result
    }

    // Produces a key-dependent record locator. Its bytes can be stored in the
    // container without exposing a stable file signature.
    func recordLocator(key: const [..] u8, kind: u32, recordId: u64)->[RecordLocatorSize] u8 fail
    {
        var context: [16] u8
        store32(&context[0], kind)
        store32(&context[4], low32(recordId))
        store32(&context[8], low32(recordId >> 32))
        store32(&context[12], 0x6163_6F6C)     // "loca", used only inside the keyed hash.

        var result: retval
        try Core.Hash.Blake2b.computeKeyed(key, context, result)
        return result
    }

    // Encrypts and authenticates one record in a single pass over the data.
    func seal(keys: const *Keys, kind: u32, recordId: u64, plaintext: const [..] u8, nonce: [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
    {
        Debug.assert(@countof(nonce) == NonceSize)
        Debug.assert(@countof(ciphertext) == @countof(plaintext))
        Debug.assert(@countof(tag) == TagSize)
        Core.Crypto.randomBytes(nonce)
        try Core.Crypto.chacha20Poly1305Seal(keys.record, nonce, plaintext, associatedData(kind, recordId), ciphertext, tag)
    }

    // Verifies and decrypts one record. Reports whether the record was authentic
    // for this key, kind, and position; `plaintext` is untouched when it was not.
    func open(keys: const *Keys, kind: u32, recordId: u64, nonce, ciphertext, tag: const [..] u8, plaintext: [..] u8)->bool fail
    {
        if @countof(nonce) != NonceSize or @countof(tag) != TagSize or @countof(ciphertext) != @countof(plaintext) do
            return false
        return Core.Crypto.chacha20Poly1305Open(keys.record, nonce, ciphertext, tag, associatedData(kind, recordId), plaintext)
    }
}

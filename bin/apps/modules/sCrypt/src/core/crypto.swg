using Core

namespace SCrypt.Crypto
{
    const SaltSize      = 32
    const NonceSize     = Core.Crypto.ChaCha20NonceSize
    const TagSize       = #sizeof(Core.Crypto.HmacSha256Digest)
    const KeySize       = Core.Crypto.ChaCha20KeySize
    const KdfIterations = #command == Swag.CompilerCommand.Test ? 1_000'u32 : 200_000'u32

    struct Keys
    {
        encryption:     [KeySize] u8
        authentication: [KeySize] u8
    }

    impl Keys
    {
        mtd clear()
        {
            Core.Crypto.secureClear(.encryption)
            Core.Crypto.secureClear(.authentication)
        }
    }

    func deriveKeys(password, salt: const [..] u8, iterations = KdfIterations)->Keys fail
    {
        var material: [KeySize * 2] u8
        Core.Crypto.pbkdf2HmacSha256(password, salt, iterations, material)

        var result: retval
        @memcpy(&result.encryption[0], &material[0], KeySize)
        @memcpy(&result.authentication[0], &material[KeySize], KeySize)
        Core.Crypto.secureClear(material)
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

    func authenticationTag(key: const [..] u8, kind: u32, recordId: u64,
                           nonce, ciphertext: const [..] u8)->[TagSize] u8
    {
        var associated: [16] u8
        store32(&associated[0], kind)
        store32(&associated[4], low32(recordId))
        store32(&associated[8], low32(recordId >> 32))
        store32(&associated[12], low32(@countof(ciphertext)))

        var hmac = Core.Crypto.HmacSha256.create(key)
        hmac.update(associated)
        hmac.update(nonce)
        hmac.update(ciphertext)
        return hmac.finalize()
    }

    func crypt(key, nonce, source: const [..] u8, destination: [..] u8) fail
    {
        Core.Crypto.chacha20Xor(key, nonce, source, destination, 1)
    }

    func seal(keys: const *Keys, kind: u32, recordId: u64, plaintext: const [..] u8,
              nonce: [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
    {
        Debug.assert(@countof(nonce) == NonceSize)
        Debug.assert(@countof(ciphertext) == @countof(plaintext))
        Debug.assert(@countof(tag) == TagSize)
        Core.Crypto.randomBytes(nonce)
        crypt(keys.encryption, nonce, plaintext, ciphertext)
        let value = authenticationTag(keys.authentication, kind, recordId, nonce, ciphertext)
        @memcpy(@dataof(tag), &value[0], TagSize)
    }

    func open(keys: const *Keys, kind: u32, recordId: u64, nonce, ciphertext, tag: const [..] u8,
              plaintext: [..] u8)->bool fail
    {
        if @countof(nonce) != NonceSize or @countof(tag) != TagSize or
           @countof(ciphertext) != @countof(plaintext) do
            return false
        var expected = authenticationTag(keys.authentication, kind, recordId, nonce, ciphertext)
        let valid = Core.Crypto.constantTimeEqual(expected, tag)
        Core.Crypto.secureClear(expected)
        if !valid do
            return false
        crypt(keys.encryption, nonce, ciphertext, plaintext)
        return true
    }
}

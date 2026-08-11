#global namespace Crypto

// Size in bytes of a ChaCha20-Poly1305 key.
public const ChaCha20Poly1305KeySize = ChaCha20KeySize

// Size in bytes of a ChaCha20-Poly1305 nonce.
public const ChaCha20Poly1305NonceSize = ChaCha20NonceSize

// Size in bytes of a ChaCha20-Poly1305 authentication tag.
public const ChaCha20Poly1305TagSize = Poly1305TagSize

// Feeds one length-prefixed part of the authenticated data, padded to the
// sixteen-byte block the tag is computed over.
private func updatePadded(mac: *Poly1305, data: const [..] u8)
{
    mac.update(data)

    let remainder = @countof(data) % Poly1305BlockSize
    if remainder
    {
        var padding: [Poly1305BlockSize] u8
        mac.update(padding[0 until Poly1305BlockSize - remainder])
    }
}

// Computes the authentication tag over the associated data and the ciphertext.
//
// The trailing lengths are what stop an attacker from moving bytes between the
// two parts while keeping the tag valid.
private func authenticate(key, nonce, associatedData, ciphertext: const [..] u8)->Poly1305Tag fail
{
    // The one-time Poly1305 key is the first half of key-stream block zero, so
    // every nonce gets a key it never shares with the payload it protects.
    var stream = try chacha20Block(key, 0, nonce)
    defer secureClear(stream)

    var mac = try Poly1305.create(stream[0 until Poly1305KeySize])
    updatePadded(&mac, associatedData)
    updatePadded(&mac, ciphertext)

    var lengths: [16] u8
    for i in 8
    {
        lengths[i]     = cast(u8) ((@countof(associatedData) >> cast(u32) (i * 8)) & 0xFF)
        lengths[8 + i] = cast(u8) ((@countof(ciphertext) >> cast(u32) (i * 8)) & 0xFF)
    }

    mac.update(lengths)
    return mac.finalize()
}

// Encrypts and authenticates `plaintext` with ChaCha20-Poly1305, RFC 8439.
//
// `key` holds 32 bytes, `nonce` 12, `tag` 16, and `ciphertext` exactly as many
// bytes as `plaintext`. `associatedData` is authenticated but not encrypted; pass
// an empty slice when there is none. `ciphertext` and `plaintext` can be the same
// slice; any other overlap is not supported.
//
// A nonce must never repeat under one key. Repeating it reveals the relationship
// between the two plaintexts and lets an observer forge tags for that key.
//
// This is a single pass over the data in each direction, unlike encrypting and
// then authenticating with separate primitives.
//
// ```swag
// var nonce: [Crypto.ChaCha20Poly1305NonceSize] u8
// try Crypto.randomBytes(nonce)
//
// var ciphertext: [5] u8
// var tag: Crypto.Poly1305Tag
// try Crypto.chacha20Poly1305Seal(key, nonce, "hello", "", ciphertext, tag)
// ```
public func chacha20Poly1305Seal(key, nonce, plaintext, associatedData: const [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
{
    if @countof(tag) != ChaCha20Poly1305TagSize do
        fail Errors.BadParameterError{"ChaCha20-Poly1305 needs a 16-byte tag"}
    if @countof(ciphertext) != @countof(plaintext) do
        fail Errors.BadParameterError{"ChaCha20-Poly1305 needs matching plaintext and ciphertext lengths"}

    // Block zero produced the one-time authentication key, so the payload starts
    // at block one.
    try chacha20Xor(key, nonce, plaintext, ciphertext, 1)

    var computed = try authenticate(key, nonce, associatedData, ciphertext)
    @memcpy(@dataof(tag), &computed[0], ChaCha20Poly1305TagSize)
    secureClear(computed)
}

// Verifies and decrypts `ciphertext` with ChaCha20-Poly1305, RFC 8439.
//
// Reports whether the tag was valid. `plaintext` is only written when it was, so
// a caller never observes unauthenticated bytes. A false result means the key,
// the nonce, the associated data, the ciphertext, or the tag does not match what
// was sealed; it does not say which.
public func chacha20Poly1305Open(key, nonce, ciphertext, tag, associatedData: const [..] u8, plaintext: [..] u8)->bool fail
{
    if @countof(tag) != ChaCha20Poly1305TagSize or @countof(ciphertext) != @countof(plaintext) do
        return false

    var computed = try authenticate(key, nonce, associatedData, ciphertext)
    defer secureClear(computed)
    if !constantTimeEqual(computed, tag) do
        return false

    try chacha20Xor(key, nonce, ciphertext, plaintext, 1)
    return true
}

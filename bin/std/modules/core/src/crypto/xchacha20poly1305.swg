#global public
#global namespace Crypto

// Size in bytes of an XChaCha20-Poly1305 key.
public const XChaCha20Poly1305KeySize = ChaCha20KeySize

// Size in bytes of an XChaCha20-Poly1305 nonce.
public const XChaCha20Poly1305NonceSize = 24

// Size in bytes of an XChaCha20-Poly1305 authentication tag.
public const XChaCha20Poly1305TagSize = Poly1305TagSize

// Encrypts and authenticates `plaintext` with XChaCha20-Poly1305.
//
// `key` holds 32 bytes, `nonce` 24, `tag` 16, and `ciphertext` exactly as many bytes as
// `plaintext`. `associatedData` is authenticated but not encrypted. Source and destination can
// be the same slice or disjoint; other overlaps are not supported. Associated data and ciphertext
// must be disjoint, as must the tag and ciphertext. A nonce must never repeat under one key. The
// extended nonce reduces accidental reuse risk but does not make reuse safe.
// Fails with [[Core.Errors.BadParameterError]] when a buffer has the wrong size.
public func xchacha20Poly1305Seal(key, nonce, plaintext, associatedData: const [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
{
    if key.count != XChaCha20Poly1305KeySize or
       nonce.count != XChaCha20Poly1305NonceSize do
        fail Errors.BadParameterError{"XChaCha20-Poly1305 needs a 32-byte key and 24-byte nonce"}
    if tag.count != XChaCha20Poly1305TagSize do
        fail Errors.BadParameterError{"XChaCha20-Poly1305 needs a 16-byte tag"}
    if ciphertext.count != plaintext.count do
        fail Errors.BadParameterError{"XChaCha20-Poly1305 needs matching plaintext and ciphertext lengths"}

    var subkey = try hchacha20(key, nonce[0 until 16])
    defer secureClear(subkey)
    var shortNonce: [ChaCha20NonceSize] u8
    Swag.memcpy(&shortNonce[4], nonce.buffer + 16, 8)
    defer secureClear(shortNonce)

    try chacha20Xor(subkey, shortNonce, plaintext, ciphertext, 1)
    var computed = try chacha20Poly1305Authenticate(subkey, shortNonce, associatedData, ciphertext)
    defer secureClear(computed)
    Swag.memcpy(tag.buffer, &computed[0], XChaCha20Poly1305TagSize)
}

// Verifies and decrypts XChaCha20-Poly1305 ciphertext.
//
// Returns false for an invalid tag, a wrong tag size, or a plaintext buffer of another length;
// destination bytes are untouched when authentication fails. Fails with
// [[Core.Errors.BadParameterError]] when `key` does not hold 32 bytes or `nonce` 24.
public func xchacha20Poly1305Open(key, nonce, ciphertext, tag, associatedData: const [..] u8, plaintext: [..] u8)->bool fail
{
    if key.count != XChaCha20Poly1305KeySize or
       nonce.count != XChaCha20Poly1305NonceSize do
        fail Errors.BadParameterError{"XChaCha20-Poly1305 needs a 32-byte key and 24-byte nonce"}
    if tag.count != XChaCha20Poly1305TagSize or ciphertext.count != plaintext.count do
        return false

    var subkey = try hchacha20(key, nonce[0 until 16])
    defer secureClear(subkey)
    var shortNonce: [ChaCha20NonceSize] u8
    Swag.memcpy(&shortNonce[4], nonce.buffer + 16, 8)
    defer secureClear(shortNonce)

    var computed = try chacha20Poly1305Authenticate(subkey, shortNonce, associatedData, ciphertext)
    defer secureClear(computed)
    if not constantTimeEqual(computed, tag) do
        return false

    try chacha20Xor(subkey, shortNonce, ciphertext, plaintext, 1)
    return true
}

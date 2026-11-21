#global if #command == Swag.CompilerCommand.Test
#global private

func xchachaHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func xchachaHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (xchachaHexDigit(text[index]) << 4) | xchachaHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

func xchachaRangeBytes(count: u64, first: u8)->Array'u8
{
    var result: #returntype
    result.resize(count)
    for index in count do
        result[index] = cast(u8, ((first + index) & 0xFF))
    return result
}

#test
{
    // The XChaCha20-Poly1305 draft vector also crosses a partial final block.
    let key                = xchachaHexBytes("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
    let nonce              = xchachaHexBytes("404142434445464748494a4b4c4d4e4f5051525354555657")
    let associatedData     = xchachaHexBytes("50515253c0c1c2c3c4c5c6c7")
    let plaintext          = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    let expectedCiphertext = xchachaHexBytes("bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b4522f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff921f9664c97637da9768812f615c68b13b52e")
    let expectedTag        = xchachaHexBytes("c0875924c1c7987947deafd8780acf49")
    var ciphertext: Array'u8
    ciphertext.resize(plaintext.count)
    var tag: [Crypto.XChaCha20Poly1305TagSize] u8
    expect Crypto.xchacha20Poly1305Seal(key.toSlice(), nonce.toSlice(), plaintext, associatedData.toSlice(), ciphertext.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext.toSlice(), expectedCiphertext.toSlice()))
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    var decrypted: Array'u8
    decrypted.resize(plaintext.count)
    let opened = expect Crypto.xchacha20Poly1305Open(key.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), decrypted.toSlice())
    Swag.require(opened)
    Swag.require(Crypto.constantTimeEqual(decrypted.toSlice(), plaintext))
}

#test
{
    // A rejected tag leaves the destination unchanged; valid in-place open succeeds.
    let key       = xchachaHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce     = xchachaHexBytes("000102030405060708090a0b0c0d0e0f1011121314151617")
    let plaintext = "authenticated in place"
    var buffer: Array'u8
    buffer.resize(plaintext.count)
    var tag: [Crypto.XChaCha20Poly1305TagSize] u8
    expect Crypto.xchacha20Poly1305Seal(key.toSlice(), nonce.toSlice(), plaintext, "context", buffer.toSlice(), tag)

    var sealed: Array'u8
    sealed.add(buffer.toSlice())
    var destination: Array'u8
    destination.resize(plaintext.count)
    Swag.memset(&destination[0], 0xA5, destination.count)
    tag[0] ^= 1
    let rejected = expect Crypto.xchacha20Poly1305Open(key.toSlice(), nonce.toSlice(), buffer.toSlice(), tag, "context", destination.toSlice())
    Swag.require(not rejected)
    for byte in destination.toSlice() do
        Swag.require(byte == 0xA5)

    tag[0] ^= 1
    let opened = expect Crypto.xchacha20Poly1305Open(key.toSlice(), nonce.toSlice(), buffer.toSlice(), tag, "context", buffer.toSlice())
    Swag.require(opened)
    Swag.require(Crypto.constantTimeEqual(buffer.toSlice(), plaintext))
    Swag.require(not Crypto.constantTimeEqual(sealed.toSlice(), plaintext))
}

#test
{
    // XChaCha20 reuses the parallel four-block path for large messages.
    Swag.setWorkerCount(4)
    var key:    [Crypto.XChaCha20Poly1305KeySize] u8
    var nonce:  [Crypto.XChaCha20Poly1305NonceSize] u8
    let plaintext = xchachaRangeBytes(2 * 65536 + 193, 0x44)
    var buffer: Array'u8
    buffer.resize(plaintext.count)
    var tag: [Crypto.XChaCha20Poly1305TagSize] u8
    expect Crypto.xchacha20Poly1305Seal(key, nonce, plaintext.toSlice(), "large payload", buffer.toSlice(), tag)
    let opened = expect Crypto.xchacha20Poly1305Open(key, nonce, buffer.toSlice(), tag, "large payload", buffer.toSlice())
    Swag.require(opened)
    Swag.require(Crypto.constantTimeEqual(buffer.toSlice(), plaintext.toSlice()))
}

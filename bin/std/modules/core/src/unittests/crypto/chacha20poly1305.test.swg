#global if #command == Swag.CompilerCommand.Test
#global private

func rangeBytes(count: u64, first: u8)->Array'u8
{
    var result: retval
    result.resize(count)
    for i in count do
        result[i] = cast(u8) ((first + i) & 0xFF)
    return result
}

#test
{
    // RFC 8439 section 2.5.2.
    let key: [32] u8 = [
        0x85, 0xD6, 0xBE, 0x78, 0x57, 0x55, 0x6D, 0x33,
        0x7F, 0x44, 0x52, 0xFE, 0x42, 0xD5, 0x06, 0xA8,
        0x01, 0x03, 0x80, 0x8A, 0xFB, 0x0D, 0xB2, 0xFD,
        0x4A, 0xBF, 0xF6, 0xAF, 0x41, 0x49, 0xF5, 0x1B]

    let tag               = expect Crypto.Poly1305.compute(key, "Cryptographic Forum Research Group")
    let expected: [16] u8 = [
        0xA8, 0x06, 0x1D, 0xC1, 0x30, 0x51, 0x36, 0xC6,
        0xC2, 0x2B, 0x8B, 0xAF, 0x0C, 0x01, 0x27, 0xA9]
    @assert(Crypto.constantTimeEqual(tag, expected))
}

#test
{
    // The incremental path must agree with the one-shot path across block
    // boundaries, and an empty message is a valid message.
    let key = rangeBytes(32, 0x40)

    let empty    = expect Crypto.Poly1305.compute(key.toSlice(), "")
    var emptyMac = expect Crypto.Poly1305.create(key.toSlice())
    @assert(Crypto.constantTimeEqual(empty, emptyMac.finalize()))

    let message = rangeBytes(97, 1)
    let oneShot = expect Crypto.Poly1305.compute(key.toSlice(), message.toSlice())

    var streamed = expect Crypto.Poly1305.create(key.toSlice())
    var offset   = 0'u64
    while offset < message.count
    {
        let chunk = Math.min(message.count - offset, 5'u64)
        streamed.update(message.toSlice()[offset until offset + chunk])
        offset += chunk
    }

    @assert(Crypto.constantTimeEqual(oneShot, streamed.finalize()))
    @assert(!Crypto.constantTimeEqual(oneShot, empty))
}

#test
{
    // RFC 8439 section 2.8.2, the full AEAD vector.
    let plaintext               = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    let key                     = rangeBytes(32, 0x80)
    let associatedData: [12] u8 = [0x50, 0x51, 0x52, 0x53, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7]
    let nonce:          [12] u8 = [0x07, 0x00, 0x00, 0x00, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]

    var ciphertext: Array'u8
    ciphertext.resize(@countof(plaintext))
    var tag: [Crypto.ChaCha20Poly1305TagSize] u8
    expect Crypto.chacha20Poly1305Seal(key.toSlice(), nonce, plaintext, associatedData, ciphertext.toSlice(), tag)

    let expectedTag: [16] u8 = [
        0x1A, 0xE1, 0x0B, 0x59, 0x4F, 0x09, 0xE2, 0x6A,
        0x7E, 0x90, 0x2E, 0xCB, 0xD0, 0x60, 0x06, 0x91]
    @assert(Crypto.constantTimeEqual(tag, expectedTag))

    let expectedHead: [16] u8 = [
        0xD3, 0x1A, 0x8D, 0x34, 0x64, 0x8E, 0x60, 0xDB,
        0x7B, 0x86, 0xAF, 0xBC, 0x53, 0xEF, 0x7E, 0xC2]
    @assert(Crypto.constantTimeEqual(ciphertext.toSlice()[0 until 16], expectedHead))

    var opened: Array'u8
    opened.resize(@countof(plaintext))
    @assert(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce, ciphertext.toSlice(), tag, associatedData, opened.toSlice()))
    @assert(Crypto.constantTimeEqual(opened.toSlice(), plaintext))
}

#test
{
    // Every input the tag covers must be able to reject the record, and a
    // rejected record must leave the destination untouched.
    let key            = rangeBytes(32, 0x11)
    let nonce          = rangeBytes(12, 0x22)
    let associatedData = rangeBytes(9, 0x33)
    let plaintext      = rangeBytes(70, 0x44)

    var ciphertext: Array'u8
    ciphertext.resize(plaintext.count)
    var tag: [Crypto.ChaCha20Poly1305TagSize] u8
    expect Crypto.chacha20Poly1305Seal(key.toSlice(), nonce.toSlice(), plaintext.toSlice(), associatedData.toSlice(), ciphertext.toSlice(), tag)
    @assert(!Crypto.constantTimeEqual(ciphertext.toSlice(), plaintext.toSlice()))

    var opened: Array'u8
    opened.resize(plaintext.count)
    @assert(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), opened.toSlice()))
    @assert(Crypto.constantTimeEqual(opened.toSlice(), plaintext.toSlice()))

    ciphertext[0] ^= 1
    @assert(!(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), opened.toSlice())))
    ciphertext[0] ^= 1

    tag[0] ^= 1
    @assert(!(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), opened.toSlice())))
    tag[0] ^= 1

    let otherAssociated = rangeBytes(9, 0x34)
    @assert(!(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, otherAssociated.toSlice(), opened.toSlice())))

    let otherNonce = rangeBytes(12, 0x23)
    @assert(!(expect Crypto.chacha20Poly1305Open(key.toSlice(), otherNonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), opened.toSlice())))

    let otherKey = rangeBytes(32, 0x12)
    @assert(!(expect Crypto.chacha20Poly1305Open(otherKey.toSlice(), nonce.toSlice(), ciphertext.toSlice(), tag, associatedData.toSlice(), opened.toSlice())))

    // An empty payload is still authenticated, which is what a metadata-only
    // record relies on.
    var emptyPayload: Array'u8
    var emptyTag:     [Crypto.ChaCha20Poly1305TagSize] u8
    expect Crypto.chacha20Poly1305Seal(key.toSlice(), nonce.toSlice(), "", associatedData.toSlice(), emptyPayload.toSlice(), emptyTag)
    @assert(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), "", emptyTag, associatedData.toSlice(), emptyPayload.toSlice()))
    emptyTag[15] ^= 0x80
    @assert(!(expect Crypto.chacha20Poly1305Open(key.toSlice(), nonce.toSlice(), "", emptyTag, associatedData.toSlice(), emptyPayload.toSlice())))
}

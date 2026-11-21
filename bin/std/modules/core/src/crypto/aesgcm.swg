#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// AES-GCM uses 96-bit nonces and 128-bit authentication tags in this API.
public const AesGcmNonceSize = 12

// AES-GCM authentication tag size in bytes.
public const AesGcmTagSize = 16

private func aesGcmGhashBlock(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    var value: [16] u8
    for index in 16 do
        value[index] = state[][index] ^ block[index]

    var product: [16] u8
    var factor = hashKey
    for byte in 16
    {
        for bit in 8
        {
            let selected = cast(u8, 0'u8 - ((value[byte] >> (7 - bit)) & 1))
            for index in 16 do
                product[index] ^= factor[index] & selected

            let lowBit = factor[15] & 1
            var carry  = 0'u8
            for index in 16
            {
                let nextCarry = factor[index] & 1
                factor[index] = (factor[index] >> 1) | (carry << 7)
                carry         = nextCarry
            }

            factor[0] ^= 0xE1'u8 & cast(u8, 0'u8 - lowBit)
        }
    }

    state[] = product
    Crypto.secureClear(value)
    Crypto.secureClear(product)
    Crypto.secureClear(factor)
}

private func aesGcmGhashData(state: *[16] u8, hashKey: [16] u8, data: const [..] u8)
{
    var offset = 0'u64
    while offset < data.count
    {
        var block: [16] u8
        let count = Math.min(data.count - offset, 16)
        Swag.memcpy(&block[0], data.buffer + offset, count)
        aesGcmGhashBlock(state, hashKey, &block[0])
        offset += count
    }
}

private func aesGcmWriteU64(destination: [*] u8, value: u64)
{
    for index in 8 do
        destination[index] = cast(u8, (value >> cast(u32, (7 - index) * 8)) & 0xFF)
}

private func aesGcmHashKey(aes: *Aes)->[16] u8 fail
{
    var zeroBlock: [16] u8
    var hashKey:   [16] u8
    try aes[].encryptBlock(zeroBlock, hashKey)
    return hashKey
}

private func aesGcmInitialHash(hashKey: [16] u8, associatedData: const [..] u8)->[16] u8 fail
{
    if associatedData.count > Swag.U64.Max / 8 do
        fail Errors.BadParameterError{"AES-GCM associated data is too large"}

    var state: [16] u8
    aesGcmGhashData(&state, hashKey, associatedData)
    return state
}

private func aesGcmTag(aes: *Aes, nonce: const [..] u8, associatedData: const [..] u8, hashKey, initialHash: [16] u8, ciphertext: const [..] u8)->[AesGcmTagSize] u8 fail
{
    if ciphertext.count > Swag.U64.Max / 8 do
        fail Errors.BadParameterError{"AES-GCM input is too large"}

    var state = initialHash
    aesGcmGhashData(&state, hashKey, ciphertext)

    var lengths: [16] u8
    aesGcmWriteU64(&lengths[0], associatedData.count * 8)
    aesGcmWriteU64(&lengths[8], ciphertext.count * 8)
    aesGcmGhashBlock(&state, hashKey, &lengths[0])

    var initialCounter: [16] u8
    Swag.memcpy(&initialCounter[0], nonce.buffer, AesGcmNonceSize)
    initialCounter[15] = 1
    var encryptedCounter: [16] u8
    try aes[].encryptBlock(initialCounter, encryptedCounter)

    var tag: #returntype
    for index in AesGcmTagSize do
        tag[index] = state[index] ^ encryptedCounter[index]
    Crypto.secureClear(state)
    Crypto.secureClear(lengths)
    Crypto.secureClear(initialCounter)
    Crypto.secureClear(encryptedCounter)
    return tag
}

private func aesGcmIncrementCounter(counter: *[16] u8)
{
    var carry = 1'u8
    for index in 4
    {
        let byteIndex = 15 - index
        let value     = cast(u16, counter[][byteIndex]) + carry
        counter[][byteIndex] = cast(u8, value & 0xFF)
        carry = cast(u8, value >> 8)
    }
}

// Encrypts with AES-GCM using a 16, 24, or 32-byte key, a 12-byte nonce, and a 16-byte tag.
//
// Never reuse a nonce with the same key. The ciphertext output must match the plaintext length;
// plaintext and ciphertext may be the same slice or disjoint, and tag output must be disjoint from
// ciphertext. Fails with [[Core.Errors.BadParameterError]] for invalid sizes or an impractically
// large payload; no authentication tag is truncated.
func aesGcmEncrypt(key, nonce, associatedData, plaintext: const [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
{
    if nonce.count != AesGcmNonceSize or
       ciphertext.count != plaintext.count or
       tag.count != AesGcmTagSize do
        fail Errors.BadParameterError{"AES-GCM needs a 12-byte nonce, matching ciphertext, and a 16-byte tag"}
    if plaintext.count > (0xFFFF_FFFE'u64 * 16) do
        fail Errors.BadParameterError{"AES-GCM payload exceeds the counter limit"}

    var aes = try Aes.create(key)
    defer aes.clear()
    var nonceCopy: [AesGcmNonceSize] u8
    defer Crypto.secureClear(nonceCopy)
    Swag.memcpy(&nonceCopy[0], nonce.buffer, AesGcmNonceSize)
    var hashKey = try aesGcmHashKey(&aes)
    defer Crypto.secureClear(hashKey)
    var initialHash = try aesGcmInitialHash(hashKey, associatedData)
    defer Crypto.secureClear(initialHash)
    var counter: [16] u8
    defer Crypto.secureClear(counter)
    Swag.memcpy(&counter[0], &nonceCopy[0], AesGcmNonceSize)
    counter[15] = 1
    var offset = 0'u64
    while offset < plaintext.count
    {
        aesGcmIncrementCounter(&counter)
        var keyStream: [16] u8
        try aes.encryptBlock(counter, keyStream)
        let count = Math.min(plaintext.count - offset, 16)
        for index in count do
            ciphertext[offset + index] = plaintext[offset + index] ^ keyStream[index]
        Crypto.secureClear(keyStream)
        offset += count
    }

    let computedTag = try aesGcmTag(&aes, nonceCopy, associatedData, hashKey, initialHash, ciphertext)
    Swag.memcpy(tag.buffer, &computedTag[0], AesGcmTagSize)
    Crypto.secureClear(computedTag)
}

// Authenticates and decrypts AES-GCM ciphertext without exposing plaintext before tag validation.
//
// Buffers must use a 16, 24, or 32-byte key, a 12-byte nonce, a 16-byte tag, and equal-length
// ciphertext and plaintext. Fails with [[Core.Errors.BadParameterError]] for invalid sizes,
// oversized payloads, or an invalid authentication tag; destination bytes are untouched on tag failure.
func aesGcmDecrypt(key, nonce, associatedData, ciphertext: const [..] u8, tag: const [..] u8, plaintext: [..] u8) fail
{
    if nonce.count != AesGcmNonceSize or
       tag.count != AesGcmTagSize or
       plaintext.count != ciphertext.count do
        fail Errors.BadParameterError{"AES-GCM needs a 12-byte nonce, a 16-byte tag, and matching plaintext"}
    if ciphertext.count > (0xFFFF_FFFE'u64 * 16) do
        fail Errors.BadParameterError{"AES-GCM payload exceeds the counter limit"}

    var aes = try Aes.create(key)
    defer aes.clear()
    var nonceCopy: [AesGcmNonceSize] u8
    defer Crypto.secureClear(nonceCopy)
    Swag.memcpy(&nonceCopy[0], nonce.buffer, AesGcmNonceSize)
    var hashKey = try aesGcmHashKey(&aes)
    defer Crypto.secureClear(hashKey)
    var initialHash = try aesGcmInitialHash(hashKey, associatedData)
    defer Crypto.secureClear(initialHash)
    let computedTag = try aesGcmTag(&aes, nonceCopy, associatedData, hashKey, initialHash, ciphertext)
    defer Crypto.secureClear(computedTag)
    if not Crypto.constantTimeEqual(computedTag, tag)
    {
        fail Errors.BadParameterError{"AES-GCM authentication failed"}
    }

    var counter: [16] u8
    defer Crypto.secureClear(counter)
    Swag.memcpy(&counter[0], &nonceCopy[0], AesGcmNonceSize)
    counter[15] = 1
    var offset = 0'u64
    while offset < ciphertext.count
    {
        aesGcmIncrementCounter(&counter)
        var keyStream: [16] u8
        try aes.encryptBlock(counter, keyStream)
        let count = Math.min(ciphertext.count - offset, 16)
        for index in count do
            plaintext[offset + index] = ciphertext[offset + index] ^ keyStream[index]
        Crypto.secureClear(keyStream)
        offset += count
    }
}

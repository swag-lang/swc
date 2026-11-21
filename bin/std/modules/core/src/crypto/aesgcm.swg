#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// AES-GCM uses 96-bit nonces and 128-bit authentication tags in this API.
public const AesGcmNonceSize = 12

// AES-GCM authentication tag size in bytes.
public const AesGcmTagSize = 16

private func aesGcmTogglePolynomialBit(product: *[4] u64, position: u32, mask: u64)
{
    let word = position / 64
    let bit  = position % 64
    product[][word] ^= (1'u64 << bit) & mask
}

internal func aesGcmGhashBlockClmul(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    var value:      [2] u64
    var key:        [2] u64
    var stateWords: [2] u64
    var blockWords: [2] u64
    var keyWords:   [2] u64
    Swag.memcpy(&stateWords[0], &state[][0], 16)
    Swag.memcpy(&blockWords[0], block, 16)
    Swag.memcpy(&keyWords[0], &hashKey[0], 16)
    for index in 2
    {
        value[index] = Math.reverse(Math.bigEndianToNative(stateWords[index] ^ blockWords[index]))
        key[index]   = Math.reverse(Math.bigEndianToNative(keyWords[index]))
    }

    let left  = cast(Math.Simd.U64x2, value)
    let right = cast(Math.Simd.U64x2, key)
    var lowLow:   [2] u64
    var lowHigh:  [2] u64
    var highLow:  [2] u64
    var highHigh: [2] u64
    Math.Simd.store(&lowLow[0], Math.Simd.clmulLowLow(left, right))
    Math.Simd.store(&lowHigh[0], Math.Simd.clmulLowHigh(left, right))
    Math.Simd.store(&highLow[0], Math.Simd.clmulHighLow(left, right))
    Math.Simd.store(&highHigh[0], Math.Simd.clmulHighHigh(left, right))

    var product: [4] u64
    product[0] = lowLow[0]
    product[1] = lowLow[1] ^ lowHigh[0] ^ highLow[0]
    product[2] = highHigh[0] ^ lowHigh[1] ^ highLow[1]
    product[3] = highHigh[1]

    // Reduce x^255..x^128 by x^128 + x^7 + x^2 + x + 1 in a fixed bit schedule.
    for bit in 128
    {
        let position = 128'u32 + (127 - bit)
        let selected = 0'u64 - ((product[position / 64] >> (position % 64)) & 1)
        aesGcmTogglePolynomialBit(&product, position, selected)
        aesGcmTogglePolynomialBit(&product, position - 128, selected)
        aesGcmTogglePolynomialBit(&product, position - 127, selected)
        aesGcmTogglePolynomialBit(&product, position - 126, selected)
        aesGcmTogglePolynomialBit(&product, position - 121, selected)
    }

    var output: [2] u64
    output[0] = Math.nativeToBigEndian(Math.reverse(product[0]))
    output[1] = Math.nativeToBigEndian(Math.reverse(product[1]))
    Swag.memcpy(&state[][0], &output[0], 16)
    Crypto.secureClear(value)
    Crypto.secureClear(key)
    Crypto.secureClear(stateWords)
    Crypto.secureClear(blockWords)
    Crypto.secureClear(keyWords)
    Crypto.secureClear(lowLow)
    Crypto.secureClear(lowHigh)
    Crypto.secureClear(highLow)
    Crypto.secureClear(highHigh)
    Crypto.secureClear(product)
    Crypto.secureClear(output)
}

internal func aesGcmGhashBlockScalar(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    var value:   [2] u64
    var factor:  [2] u64
    var product: [2] u64
    var input:   [2] u64
    Swag.memcpy(&value[0], &state[][0], 16)
    Swag.memcpy(&input[0], block, 16)
    Swag.memcpy(&factor[0], &hashKey[0], 16)
    for index in 2
    {
        value[index]  = Math.bigEndianToNative(value[index] ^ input[index])
        factor[index] = Math.bigEndianToNative(factor[index])
    }

    for word in 2
    {
        for bit in 64
        {
            let selected = 0'u64 - ((value[word] >> (63 - bit)) & 1)
            product[0] ^= factor[0] & selected
            product[1] ^= factor[1] & selected

            let lowBit = factor[1] & 1
            factor[1] = (factor[1] >> 1) | (factor[0] << 63)
            factor[0] = (factor[0] >> 1) ^ (0xE100000000000000'u64 & (0'u64 - lowBit))
        }
    }

    for index in 2 do
        value[index] = Math.nativeToBigEndian(product[index])
    Swag.memcpy(&state[][0], &value[0], 16)
    Crypto.secureClear(product)
    Crypto.secureClear(factor)
    Crypto.secureClear(input)
    Crypto.secureClear(value)
}

private func aesGcmGhashBlock(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    #static if not BIG_ENDIAN
    {
        aesGcmGhashBlockClmul(state, hashKey, block)
    }
    else
    {
        aesGcmGhashBlockScalar(state, hashKey, block)
    }
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

private func aesGcmCryptBlocks(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64) fail
{
    var block    = firstBlock
    let endBlock = firstBlock + blockCount
    while block < endBlock
    {
        var counter: [16] u8
        Swag.memcpy(&counter[0], nonce.buffer, AesGcmNonceSize)
        let counterValue = cast(u32, block + 2)
        counter[12] = Math.byteAt(counterValue, 3)
        counter[13] = Math.byteAt(counterValue, 2)
        counter[14] = Math.byteAt(counterValue, 1)
        counter[15] = Math.byteAt(counterValue, 0)

        var keyStream: [16] u8
        try aes[].encryptBlock(counter, keyStream)
        let offset = block * 16
        let count  = Math.min(source.count - offset, 16)
        for index in count do
            destination[offset + index] = source[offset + index] ^ keyStream[index]
        Crypto.secureClear(counter)
        Crypto.secureClear(keyStream)
        block += 1
    }
}

private func aesGcmCrypt(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8) fail
{
    const ParallelThreshold = 64 * 1024
    const BatchBlocks       = 1024
    let blockCount = source.count / 16 + cast(u64, (source.count % 16) != 0)
    if source.count < ParallelThreshold
    {
        try aesGcmCryptBlocks(aes, nonce, source, destination, 0, blockCount)
        return
    }

    let batchCount = blockCount / BatchBlocks + cast(u64, (blockCount % BatchBlocks) != 0)
    catch parallel for |&aes, &nonce, &source, &destination, blockCount| batch in batchCount
    {
        let firstBlock = batch * BatchBlocks
        let count      = Math.min(blockCount - firstBlock, BatchBlocks)
        try aesGcmCryptBlocks(aes, nonce, source, destination, firstBlock, count)
    }
    {
        fail Swag.err
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
    try aesGcmCrypt(&aes, nonceCopy, plaintext, ciphertext)

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

    try aesGcmCrypt(&aes, nonceCopy, ciphertext, plaintext)
}

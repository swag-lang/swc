#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES-GCM uses 96-bit nonces and 128-bit authentication tags in this API.
public const AesGcmNonceSize = 12

// AES-GCM authentication tag size in bytes.
public const AesGcmTagSize = 16

#[Swag.Inline]
private func aesGcmGhashMultiply(value, key: U64x2)->U64x2
{
    const Polynomial = cast(U64x2, [0x87'u64, 0])
    const Zero       = cast(U64x2, [0'u64, 0])
    let cross = clmulLowHigh(value, key) ^ clmulHighLow(value, key)
    let low   = clmulLowLow(value, key) ^ align(Zero, cross, 8)
    let high  = clmulHighHigh(value, key) ^ align(cross, Zero, 8)

    // Replacing x^128 by x^7 + x^2 + x + 1 folds the upper 128 bits into the lower half.
    // Fold the overflow once more. Its degree is at most six, so no third fold is needed.
    let foldLow  = clmulLowLow(high, Polynomial)
    let foldHigh = clmulHighLow(high, Polynomial)
    let overflow = clmulHighLow(foldHigh, Polynomial)
    return low ^ foldLow ^ align(Zero, foldHigh, 8) ^ overflow
}

internal func aesGcmGhashBlockClmul(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    // GHASH assigns its first byte's most-significant bit to coefficient zero.
    // Reverse bits within each byte to match the coefficient order used by CLMUL.
    let value   = cast #bit (U64x2, Math.reverse(load(&state[][0]) ^ load(block)))
    let key     = cast #bit (U64x2, Math.reverse(load(&hashKey[0])))
    let product = aesGcmGhashMultiply(value, key)
    store(&state[][0], Math.reverse(cast #bit (U8x16, product)))
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
        if Swag.hasCpuFeature(.CarrylessMultiply)
        {
            aesGcmGhashBlockClmul(state, hashKey, block)
            return
        }
    }

    aesGcmGhashBlockScalar(state, hashKey, block)
}

private func aesGcmGhashData(state: *[16] u8, hashKey: [16] u8, data: const [..] u8)
{
    if data.count == 0 do
        return

    let fullBlockBytes = data.count & ~15'u64
    let tailBytes      = data.count - fullBlockBytes
    let source         = data.buffer
    var tail: [16] u8
    if tailBytes != 0 do
        Swag.memcpy(&tail[0], source + fullBlockBytes, tailBytes)

    #static if not BIG_ENDIAN
    {
        if Swag.hasCpuFeature(.CarrylessMultiply)
        {
            let key         = cast #bit (U64x2, Math.reverse(load(&hashKey[0])))
            var accumulator = cast #bit (U64x2, Math.reverse(load(&state[][0])))
            for block in fullBlockBytes / 16
            {
                let value = cast #bit (U64x2, Math.reverse(load(source + block * 16)))
                accumulator = aesGcmGhashMultiply(accumulator ^ value, key)
            }

            if tailBytes != 0
            {
                let value = cast #bit (U64x2, Math.reverse(load(&tail[0])))
                accumulator = aesGcmGhashMultiply(accumulator ^ value, key)
            }

            store(&state[][0], Math.reverse(cast #bit (U8x16, accumulator)))
            return
        }
    }

    for block in fullBlockBytes / 16 do
        aesGcmGhashBlockScalar(state, hashKey, source + block * 16)
    if tailBytes != 0 do
        aesGcmGhashBlockScalar(state, hashKey, &tail[0])
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

private func aesGcmCryptBlocksHardware(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64)
{
    #[Swag.Inline]
    func counter(prefix: U32x4, block: u64)->U8x16
    {
        var words = prefix
        words[3] = Swag.byteSwap(cast(u32, block + 2))
        return cast #bit (U8x16, words)
    }

    // Only the last 32 bits of the nonce's counter block change between AES inputs.
    var initial: [AesBlockSize] u8
    Swag.memcpy(&initial[0], nonce.buffer, AesGcmNonceSize)
    let prefix           = cast #bit (U32x4, load(&initial[0]))
    let sourceBytes      = source.buffer
    let destinationBytes = destination.buffer
    let endBlock         = firstBlock + blockCount
    let fullBlockEnd     = Math.min(endBlock, source.count / AesBlockSize)
    var block            = firstBlock
    while block + 4 <= fullBlockEnd
    {
        let offset = block * AesBlockSize
        aes[].xorFourHardware(counter(prefix, block),
                              counter(prefix, block + 1),
                              counter(prefix, block + 2),
                              counter(prefix, block + 3),
                              sourceBytes + offset,
                              destinationBytes + offset)
        block += 4
    }

    while block < fullBlockEnd
    {
        let offset = block * AesBlockSize
        let stream = aes[].encryptBlockHardware(counter(prefix, block))
        store(destinationBytes + offset, stream ^ load(sourceBytes + offset))
        block += 1
    }

    if block < endBlock
    {
        var tail: [16] u8
        store(&tail[0], aes[].encryptBlockHardware(counter(prefix, block)))
        let offset = block * AesBlockSize
        for i in source.count - offset do
            destinationBytes[offset + i] = sourceBytes[offset + i] ^ tail[i]
        Crypto.secureClear(tail)
    }
}

private func aesGcmCryptBlocks(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64) fail
{
    if aes[].usesHardwareRounds()
    {
        aesGcmCryptBlocksHardware(aes, nonce, source, destination, firstBlock, blockCount)
        return
    }

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
    if source.count < ParallelThreshold or Swag.workerCount() <= 1
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

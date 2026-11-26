#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES-GCM uses 96-bit nonces and 128-bit authentication tags in this API.
public const AesGcmNonceSize = 12

// AES-GCM authentication tag size in bytes.
public const AesGcmTagSize = 16

#[Swag.Inline]
private func aesGcmReverseBytes(value: U8x16)->U8x16
{
    const Order = cast(U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    return shuffle(value, Order)
}

#[Swag.Inline]
private func aesGcmGhashPrepareKey(hashKey: [16] u8)->U64x2
{
    const Reciprocal = cast(U64x2, [1'u64, 0xC200_0000_0000_0000])
    const Zero       = cast(U64x2, [0'u64, 0])
    const HighLanes  = cast(U64x2, [1'u64, 1])

    // Reversing bytes maps GHASH bit numbering to the reciprocal polynomial.
    // Multiply by x in that field to account for the normalization in reduction.
    let reversed = cast #bit (U64x2, aesGcmReverseBytes(load(&hashKey[0])))
    let carry    = reversed >> 63
    let mask     = Zero - permute(carry, HighLanes)
    return ((reversed << 1) | align(Zero, carry, 8)) ^ (mask & Reciprocal)
}

#[Swag.Inline]
private func aesGcmGhashReduce(low, high: U64x2)->U64x2
{
    const Polynomial = cast(U64x2, [0xC200_0000_0000_0000'u64, 0])
    const Zero       = cast(U64x2, [0'u64, 0])

    // The reciprocal polynomial is x^128 + x^127 + x^126 + x^121 + 1.
    // Cancel the low words in succession to divide by x^128. The prepared key
    // includes an extra x so the result is still in the reflected representation.
    let correction = clmulLowLow(low, Polynomial)
    let quotient   = low ^ align(Zero, correction, 8)
    let second     = clmulHighLow(quotient, Polynomial)
    return high ^ low ^ align(correction, correction, 8) ^ second
}

#[Swag.Inline]
private func aesGcmGhashReduceProducts(low, high, cross: U64x2)->U64x2
{
    const Zero = cast(U64x2, [0'u64, 0])
    return aesGcmGhashReduce(low ^ align(Zero, cross, 8), high ^ align(cross, Zero, 8))
}

#[Swag.Inline]
private func aesGcmGhashAddProduct(low, high, cross: *U64x2, value, key: U64x2)
{
    low[]   ^= clmulLowLow(value, key)
    high[]  ^= clmulHighHigh(value, key)
    cross[] ^= clmulLowHigh(value, key) ^ clmulHighLow(value, key)
}

#[Swag.Inline]
private func aesGcmGhashMultiply(value, key: U64x2)->U64x2
{
    var low, high, cross: U64x2
    aesGcmGhashAddProduct(&low, &high, &cross, value, key)
    return aesGcmGhashReduceProducts(low, high, cross)
}

#[Swag.Inline]
private func aesGcmGhashLoad(source: const [*] u8)->U64x2
{
    return cast #bit (U64x2, aesGcmReverseBytes(load(source)))
}

internal func aesGcmGhashBlockClmul(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    let value   = cast #bit (U64x2, aesGcmReverseBytes(load(&state[][0]) ^ load(block)))
    let product = aesGcmGhashMultiply(value, aesGcmGhashPrepareKey(hashKey))
    store(&state[][0], aesGcmReverseBytes(cast #bit (U8x16, product)))
}

#[Swag.Inline]
private func aesGcmPolynomialMultiply32(x, y: u32)->u64
{
    const NibbleLow = 0x1111_1111_1111_1111'u64
    let x0 = cast(u64, x) & NibbleLow
    let x1 = cast(u64, x) & (NibbleLow << 1)
    let x2 = cast(u64, x) & (NibbleLow << 2)
    let x3 = cast(u64, x) & (NibbleLow << 3)
    let y0 = cast(u64, y) & NibbleLow
    let y1 = cast(u64, y) & (NibbleLow << 1)
    let y2 = cast(u64, y) & (NibbleLow << 2)
    let y3 = cast(u64, y) & (NibbleLow << 3)

    // A product combines at most eight bits per coefficient. The four-bit spacing
    // keeps carries from changing the parity of the next coefficient.
    let p0 = (x0 * y0 ^ x1 * y3 ^ x2 * y2 ^ x3 * y1) & NibbleLow
    let p1 = (x0 * y1 ^ x1 * y0 ^ x2 * y3 ^ x3 * y2) & (NibbleLow << 1)
    let p2 = (x0 * y2 ^ x1 * y1 ^ x2 * y0 ^ x3 * y3) & (NibbleLow << 2)
    let p3 = (x0 * y3 ^ x1 * y2 ^ x2 * y1 ^ x3 * y0) & (NibbleLow << 3)
    return p0 | p1 | p2 | p3
}

#[Swag.Inline]
private func aesGcmPolynomialMultiply64(x, y: u64)->{low: u64, high: u64}
{
    let x0    = cast(u32, x)
    let x1    = cast(u32, x >> 32)
    let y0    = cast(u32, y)
    let y1    = cast(u32, y >> 32)
    let low   = aesGcmPolynomialMultiply32(x0, y0)
    let high  = aesGcmPolynomialMultiply32(x1, y1)
    let cross = aesGcmPolynomialMultiply32(x0 ^ x1, y0 ^ y1) ^ low ^ high
    return {low ^ (cross << 32), high ^ (cross >> 32)}
}

#[Swag.Inline]
private func aesGcmPolynomialFold(low, high: u64)->{low: u64, high: u64}
{
    let carryLow  = (low >> 63) ^ (low >> 62) ^ (low >> 57)
    let carryHigh = (high >> 63) ^ (high >> 62) ^ (high >> 57)
    let combined  = low ^ carryHigh
    return {combined ^ (combined << 1) ^ (combined << 2) ^ (combined << 7),
            high ^ (high << 1) ^ (high << 2) ^ (high << 7) ^ carryLow}
}

#[Swag.Inline]
private func aesGcmPolynomialWords(bytes: U8x16)->U64x2
{
    let words = cast #bit (U64x2, Math.reverse(bytes))
    #static if BIG_ENDIAN do
        return Swag.byteSwap(words)
    else do
        return words
}

#[Swag.Inline]
private func aesGcmPolynomialBytes(words: U64x2)->U8x16
{
    #static if BIG_ENDIAN do
        return Math.reverse(cast #bit (U8x16, Swag.byteSwap(words)))
    else do
        return Math.reverse(cast #bit (U8x16, words))
}

private func aesGcmGhashMultiplyScalar(value, key: U64x2)->U64x2
{
    let low       = aesGcmPolynomialMultiply64(value[0], key[0])
    let high      = aesGcmPolynomialMultiply64(value[1], key[1])
    let middle    = aesGcmPolynomialMultiply64(value[0] ^ value[1], key[0] ^ key[1])
    let crossLow  = middle.low ^ low.low ^ high.low
    let crossHigh = middle.high ^ low.high ^ high.high

    // The high half folds through x^128 = x^7 + x^2 + x + 1.
    let folded = aesGcmPolynomialFold(high.low ^ crossHigh, high.high)
    var product: U64x2
    product[0] = low.low ^ folded.low
    product[1] = low.high ^ crossLow ^ folded.high
    return product
}

internal func aesGcmGhashBlockScalar(state: *[16] u8, hashKey: [16] u8, block: const [*] u8)
{
    var value = aesGcmPolynomialWords(load(&state[][0]) ^ load(block))
    var key   = aesGcmPolynomialWords(load(&hashKey[0]))
    store(&state[][0], aesGcmPolynomialBytes(aesGcmGhashMultiplyScalar(value, key)))
    Crypto.secureClear(Swag.makeSlice(&key, 1))
    Crypto.secureClear(Swag.makeSlice(&value, 1))
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
            let key         = aesGcmGhashPrepareKey(hashKey)
            var accumulator = aesGcmGhashLoad(&state[][0])
            var offset      = 0'u64
            if fullBlockBytes >= 128
            {
                // Expand four steps of the recurrence so the products share one reduction.
                let key2 = aesGcmGhashMultiply(key, key)
                let key3 = aesGcmGhashMultiply(key2, key)
                let key4 = aesGcmGhashMultiply(key2, key2)
                while offset + 64 <= fullBlockBytes
                {
                    var low, high, cross: U64x2
                    aesGcmGhashAddProduct(&low, &high, &cross, accumulator ^ aesGcmGhashLoad(source + offset), key4)
                    aesGcmGhashAddProduct(&low, &high, &cross, aesGcmGhashLoad(source + offset + 16), key3)
                    aesGcmGhashAddProduct(&low, &high, &cross, aesGcmGhashLoad(source + offset + 32), key2)
                    aesGcmGhashAddProduct(&low, &high, &cross, aesGcmGhashLoad(source + offset + 48), key)
                    accumulator = aesGcmGhashReduceProducts(low, high, cross)
                    offset      += 64
                }
            }

            while offset < fullBlockBytes
            {
                accumulator = aesGcmGhashMultiply(accumulator ^ aesGcmGhashLoad(source + offset), key)
                offset      += 16
            }

            if tailBytes != 0
            {
                let value = cast #bit (U64x2, aesGcmReverseBytes(load(&tail[0])))
                accumulator = aesGcmGhashMultiply(accumulator ^ value, key)
            }

            store(&state[][0], aesGcmReverseBytes(cast #bit (U8x16, accumulator)))
            return
        }
    }

    var polynomialKey     = aesGcmPolynomialWords(load(&hashKey[0]))
    var scalarAccumulator = aesGcmPolynomialWords(load(&state[][0]))
    for block in fullBlockBytes / 16
    {
        let value = aesGcmPolynomialWords(load(source + block * 16))
        scalarAccumulator = aesGcmGhashMultiplyScalar(scalarAccumulator ^ value, polynomialKey)
    }

    if tailBytes != 0
    {
        let value = aesGcmPolynomialWords(load(&tail[0]))
        scalarAccumulator = aesGcmGhashMultiplyScalar(scalarAccumulator ^ value, polynomialKey)
    }

    store(&state[][0], aesGcmPolynomialBytes(scalarAccumulator))
    Crypto.secureClear(Swag.makeSlice(&polynomialKey, 1))
    Crypto.secureClear(Swag.makeSlice(&scalarAccumulator, 1))
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
    if aes[].usesHardwareRounds()
    {
        var initial: [AesBlockSize] u8
        Swag.memcpy(&initial[0], nonce.buffer, AesGcmNonceSize)
        let prefix = cast #bit (U64x2, load(&initial[0]))
        aesXorCounterBlocksHardware'32(aes, prefix, source, destination, firstBlock, blockCount)
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

#global public
#global namespace Crypto

using Core.Errors

#[Swag.Inline]
private func(T) restorePbkdf2Hmac(hmac: *T, prefix: const *T)
{
    hmac.inner       = prefix.inner
    hmac.outer       = prefix.outer
    hmac.initialized = true
}

#[Swag.Inline]
private func(DigestWords: u64, Accumulate: bool) pbkdf2Sha2Encode(words: const [*] u32, block, result: [*] u32)
{
    const VectorWords = 4
    let low = Math.nativeToBigEndian(Math.Simd.load(words))
    Math.Simd.store(block, low)
    #static if Accumulate do
        Math.Simd.store(result, Math.Simd.load(result) ^ low)

    #static if DigestWords == 8
    {
        let high = Math.nativeToBigEndian(Math.Simd.load(words + VectorWords))
        Math.Simd.store(block + VectorWords, high)
        #static if Accumulate do
            Math.Simd.store(result + VectorWords, Math.Simd.load(result + VectorWords) ^ high)
    }
    else
    {
        for word in VectorWords until DigestWords
        {
            let value = Math.nativeToBigEndian(words[word])
            block[word] = value
            #static if Accumulate do
                result[word] ^= value
        }
    }
}

// Each inner and outer MAC after the first PBKDF2 iteration hashes one
// digest after a precomputed key pad. The final block length is fixed.
private func(DigestSize: u64) repeatPbkdf2Sha2(inner, outer: const *[8] u32, first: const *[DigestSize] u8, result: *[DigestSize] u8, rounds: u32)
{
    const ShaBlockSize = 64
    const DigestWords  = DigestSize / #sizeof(u32)
    const FinalLength  = (ShaBlockSize + DigestSize) * 8

    var block: [ShaBlockSize] u8
    defer secureClear(block)
    Swag.memcpy(block.buffer, first[].buffer, DigestSize)
    block[DigestSize] = 0x80
    cast([*] u64, block.buffer)[7] = Math.nativeToBigEndian(FinalLength)

    var hash: Hash.Sha256
    defer secureClear(hash.state)
    let words  = cast([*] u32, block.buffer)
    let output = cast([*] u32, result[].buffer)
    for rounds
    {
        hash.state = inner[]
        hash.transformBlocks(block, 1)
        pbkdf2Sha2Encode'(DigestWords, false)(hash.state.buffer, words, output)

        hash.state = outer[]
        hash.transformBlocks(block, 1)
        pbkdf2Sha2Encode'(DigestWords, true)(hash.state.buffer, words, output)
    }
}

#[Swag.Inline]
private func(DigestSize: u64, Accumulate: bool) pbkdf2Sha512Encode(words: const [*] u64, block, result: [*] u64)
{
    const PairCount = DigestSize / #sizeof(Math.Simd.U64x2)
    for pair in PairCount
    {
        let word   = pair * 2
        let digest = Math.nativeToBigEndian(Math.Simd.load(words + word))
        Math.Simd.store(block + word, digest)
        #static if Accumulate do
            Math.Simd.store(result + word, Math.Simd.load(result + word) ^ digest)
    }
}

// Both SHA-384 and SHA-512 fit their repeated HMAC digest in one final block.
private func(DigestSize: u64) repeatPbkdf2Sha512(inner, outer: const *[8] u64, first: const *[DigestSize] u8, result: *[DigestSize] u8, rounds: u32)
{
    const FinalLength = (Hash.Sha512BlockSize + DigestSize) * 8
    var block: [Hash.Sha512BlockSize] u8
    defer secureClear(block)
    Swag.memcpy(block.buffer, first[].buffer, DigestSize)
    block[DigestSize] = 0x80
    cast([*] u64, block.buffer)[15] = Math.nativeToBigEndian(FinalLength)

    var hash: Hash.Sha512
    defer hash.clear()
    let words  = cast([*] u64, block.buffer)
    let output = cast([*] u64, result[].buffer)
    for rounds
    {
        let innerDigest = hash.compressHmacDigestBlock(inner, block)
        pbkdf2Sha512Encode'(DigestSize, false)(innerDigest, words, output)
        let outerDigest = hash.compressHmacDigestBlock(outer, block)
        pbkdf2Sha512Encode'(DigestSize, true)(outerDigest, words, output)
    }
}

private func(Hmac, DigestSize: u64) derivePbkdf2(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return
    if salt.count > Swag.U64.Max - 4 do
        fail OverflowError{"PBKDF2 salt is too large"}

    let blockCount = ((destination.count - 1) / DigestSize) + 1
    if blockCount > Swag.U32.Max do
        fail OverflowError{"PBKDF2 output exceeds its maximum length"}

    // Capture both inputs before any output write. Later iterations only need
    // the keyed pads, while each output block starts with the salted prefix.
    let keyed = Hmac.create(password)
    var salted: Hmac
    restorePbkdf2Hmac(&salted, &keyed)
    salted.update(salt)

    var hmac: Hmac
    var outputOffset = 0'u64
    for block in 1 to blockCount
    {
        let suffix = Math.nativeToBigEndian(cast(u32, block))
        restorePbkdf2Hmac(&hmac, &salted)
        hmac.update(Swag.makeSlice(cast(const [*] u8, &suffix), #sizeof(u32)))
        var current = hmac.finalize()
        var result  = current
        if iterations > 1
        {
            #static if Hmac == HmacSha224
            {
                repeatPbkdf2Sha2'DigestSize(keyed.inner.hmacPrefixState(), keyed.outer.hmacPrefixState(), &current, &result, iterations - 1)
            }
            elif Hmac == HmacSha256
            {
                repeatPbkdf2Sha2'DigestSize(&keyed.inner.state, &keyed.outer.state, &current, &result, iterations - 1)
            }
            else
            {
                repeatPbkdf2Sha512'DigestSize(keyed.inner.hmacPrefixState(), keyed.outer.hmacPrefixState(), &current, &result, iterations - 1)
            }
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, result.buffer, count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-256 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
// `password` may overlap `destination`; its original bytes are preserved for every output block.
func pbkdf2HmacSha256(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    try derivePbkdf2'(HmacSha256, #sizeof(HmacSha256Digest))(password, salt, iterations, destination)
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-224 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha224(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    try derivePbkdf2'(HmacSha224, #sizeof(HmacSha224Digest))(password, salt, iterations, destination)
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-384 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha384(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    try derivePbkdf2'(HmacSha384, #sizeof(HmacSha384Digest))(password, salt, iterations, destination)
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-512 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha512(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    try derivePbkdf2'(HmacSha512, #sizeof(HmacSha512Digest))(password, salt, iterations, destination)
}

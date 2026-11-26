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
private func(DigestSize: u64) pbkdf2AccumulateDigest(result, current: [*] u8)
{
    const VectorSize  = #sizeof(Math.Simd.U8x16)
    const VectorCount = DigestSize / VectorSize
    for index in VectorCount
    {
        let offset = index * VectorSize
        Math.Simd.store(result + offset, Math.Simd.load(result + offset) ^ Math.Simd.load(current + offset))
    }

    const TailOffset = VectorCount * VectorSize
    for index in TailOffset until DigestSize do
        result[index] ^= current[index]
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
        for iterations - 1
        {
            restorePbkdf2Hmac(&hmac, &keyed)
            hmac.update(current)
            current = hmac.finalize()
            pbkdf2AccumulateDigest'DigestSize(result.buffer, current.buffer)
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

#global public
#global namespace Crypto

using Core.Errors

private func accumulateDigest(result, current: [*] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    Math.Simd.store(result, Math.Simd.load(result) ^ Math.Simd.load(current))
    Math.Simd.store(result + VectorSize, Math.Simd.load(result + VectorSize) ^ Math.Simd.load(current + VectorSize))
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-256 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha256(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return

    const DigestSize = #sizeof(HmacSha256Digest)
    let blockCount = ((destination.count - 1) / DigestSize) + 1
    if blockCount > Swag.U32.Max do
        fail OverflowError{"PBKDF2 output exceeds its maximum length"}

    var input: Array'u8
    input.reserve(salt.count + 4)
    input.add(salt)
    input.resize(salt.count + 4)

    var outputOffset = 0'u64
    for block in 1 to blockCount
    {
        let blockIndex = cast(u32, block)
        let suffix     = input.count - 4
        input[suffix + 0] = Math.byteAt(blockIndex, 3)
        input[suffix + 1] = Math.byteAt(blockIndex, 2)
        input[suffix + 2] = Math.byteAt(blockIndex, 1)
        input[suffix + 3] = Math.byteAt(blockIndex, 0)

        var current = HmacSha256.compute(password, input.toSlice())
        var result  = current
        for iterations - 1
        {
            current = HmacSha256.compute(password, current)
            accumulateDigest(result.buffer, current.buffer)
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

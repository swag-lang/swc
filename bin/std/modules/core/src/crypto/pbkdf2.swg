#global public
#global namespace Crypto

using Core.Errors

private func accumulateDigest(result, current: [*] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    Math.Simd.store(result, Math.Simd.load(result) ^ Math.Simd.load(current))
    Math.Simd.store(result + VectorSize, Math.Simd.load(result + VectorSize) ^ Math.Simd.load(current + VectorSize))
}

// Derives `destination` with PBKDF2-HMAC-SHA-256.
//
// `iterations` needs at least one iteration. An empty destination succeeds without writing.
func pbkdf2HmacSha256(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if !iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if !destination.count do
        return

    const digestSize = #sizeof(HmacSha256Digest)
    let blockCount = ((destination.count - 1) / digestSize) + 1
    if blockCount > Swag.U32.Max do
        fail OverflowError{"PBKDF2 output exceeds its maximum length"}

    var input: Array'u8
    input.reserve(salt.count + 4)
    input.add(salt)
    input.resize(salt.count + 4)

    var outputOffset = 0'u64
    for block in 1 to blockCount
    {
        let blockIndex = cast(u32) block
        let suffix     = input.count - 4
        input[suffix + 0] = cast(u8) ((blockIndex >> 24) & 0xFF)
        input[suffix + 1] = cast(u8) ((blockIndex >> 16) & 0xFF)
        input[suffix + 2] = cast(u8) ((blockIndex >> 8) & 0xFF)
        input[suffix + 3] = cast(u8) (blockIndex & 0xFF)

        var current = HmacSha256.compute(password, input.toSlice())
        var result  = current
        for iteration in 1 until iterations
        {
            discard iteration
            current = HmacSha256.compute(password, current)
            accumulateDigest(result.buffer, current.buffer)
        }

        let count = Math.min(destination.count - outputOffset, digestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

#global public
#global namespace Crypto

using Core.Errors

private func pbkdf2AccumulateDigest(result, current: [*] u8, digestSize: u64)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let vectorCount = digestSize / VectorSize
    for index in vectorCount
    {
        let offset = index * VectorSize
        Math.Simd.store(result + offset, Math.Simd.load(result + offset) ^ Math.Simd.load(current + offset))
    }

    let offset = vectorCount * VectorSize
    for index in offset until digestSize do
        result[index] ^= current[index]
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-256 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
// `password` may overlap `destination`; its original bytes are preserved for every output block.
func pbkdf2HmacSha256(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    #[Swag.Inline]
    func accumulateDigest(result, current: [*] u8)
    {
        const VectorSize = #sizeof(Math.Simd.U8x16)
        Math.Simd.store(result, Math.Simd.load(result) ^ Math.Simd.load(current))
        Math.Simd.store(result + VectorSize, Math.Simd.load(result + VectorSize) ^ Math.Simd.load(current + VectorSize))
    }

    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return
    if salt.count > Swag.U64.Max - 4 do
        fail OverflowError{"PBKDF2 salt is too large"}

    // A destination write for one block must not change the password used for later blocks.
    var passwordCopy: Array'u8
    var passwordInput    = password
    let passwordStart    = cast(u64, password.buffer)
    let destinationStart = cast(u64, destination.buffer)
    if passwordStart < destinationStart + destination.count and
       destinationStart < passwordStart + password.count
    {
        passwordCopy.add(password)
        passwordInput = passwordCopy.toSlice()
    }

    defer secureClear(passwordCopy.toSlice())

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

        var current = HmacSha256.compute(passwordInput, input.toSlice())
        var result  = current
        for iterations - 1
        {
            current = HmacSha256.compute(passwordInput, current)
            accumulateDigest(result.buffer, current.buffer)
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-224 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha224(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return
    if salt.count > Swag.U64.Max - 4 do
        fail OverflowError{"PBKDF2 salt is too large"}

    var passwordCopy: Array'u8
    var passwordInput = password
    let passwordStart = cast(u64, password.buffer)
    let outputStart   = cast(u64, destination.buffer)
    if passwordStart < outputStart + destination.count and outputStart < passwordStart + password.count
    {
        passwordCopy.add(password)
        passwordInput = passwordCopy.toSlice()
    }

    defer secureClear(passwordCopy.toSlice())

    const DigestSize = #sizeof(HmacSha224Digest)
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

        var current = HmacSha224.compute(passwordInput, input.toSlice())
        var result  = current
        for iterations - 1
        {
            current = HmacSha224.compute(passwordInput, current)
            pbkdf2AccumulateDigest(result.buffer, current.buffer, DigestSize)
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-384 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha384(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return
    if salt.count > Swag.U64.Max - 4 do
        fail OverflowError{"PBKDF2 salt is too large"}

    var passwordCopy: Array'u8
    var passwordInput = password
    let passwordStart = cast(u64, password.buffer)
    let outputStart   = cast(u64, destination.buffer)
    if passwordStart < outputStart + destination.count and outputStart < passwordStart + password.count
    {
        passwordCopy.add(password)
        passwordInput = passwordCopy.toSlice()
    }

    defer secureClear(passwordCopy.toSlice())

    const DigestSize = #sizeof(HmacSha384Digest)
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

        var current = HmacSha384.compute(passwordInput, input.toSlice())
        var result  = current
        for iterations - 1
        {
            current = HmacSha384.compute(passwordInput, current)
            pbkdf2AccumulateDigest(result.buffer, current.buffer, DigestSize)
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

// Derives a key from `password` and `salt` with PBKDF2-HMAC-SHA-512 and fills `destination` with it.
//
// `iterations` must be at least 1; zero fails with [[Core.Errors.BadParameterError]]. An empty
// `destination` succeeds without writing. Intermediate digests are cleared before returning.
func pbkdf2HmacSha512(password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    if not iterations do
        fail BadParameterError{"PBKDF2 needs at least one iteration"}
    if not destination.count do
        return
    if salt.count > Swag.U64.Max - 4 do
        fail OverflowError{"PBKDF2 salt is too large"}

    var passwordCopy: Array'u8
    var passwordInput = password
    let passwordStart = cast(u64, password.buffer)
    let outputStart   = cast(u64, destination.buffer)
    if passwordStart < outputStart + destination.count and outputStart < passwordStart + password.count
    {
        passwordCopy.add(password)
        passwordInput = passwordCopy.toSlice()
    }

    defer secureClear(passwordCopy.toSlice())

    const DigestSize = #sizeof(HmacSha512Digest)
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

        var current = HmacSha512.compute(passwordInput, input.toSlice())
        var result  = current
        for iterations - 1
        {
            current = HmacSha512.compute(passwordInput, current)
            pbkdf2AccumulateDigest(result.buffer, current.buffer, DigestSize)
        }

        let count = Math.min(destination.count - outputOffset, DigestSize)
        Swag.memcpy(destination.buffer + outputOffset, &result[0], count)
        outputOffset += count
        secureClear(current)
        secureClear(result)
    }
}

#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of one BLAKE2s input block.
public const Blake2sBlockSize = 64

// Largest digest BLAKE2s can produce, in bytes.
public const Blake2sMaxDigestSize = 32

// Largest key BLAKE2s accepts in keyed mode, in bytes.
public const Blake2sMaxKeySize = 32

private const Blake2sIv: [8] u32 = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]

private const Blake2sSigma: [160] u8 = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
    11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
    7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
    9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
    2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
    12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
    13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
    6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
    10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]

private alias Blake2sVector = Math.Simd.U32x4

private func blake2sRounds(message: const [*] u32, state: *[4] Blake2sVector)
{
    var a = state[][0]
    var b = state[][1]
    var c = state[][2]
    var d = state[][3]

    #[Swag.Mixin]
    func mix(x, y: Blake2sVector)
    {
        a = (a + x) + b
        d = Swag.ror(d ^ a, 16_u8)
        c += d
        b = Swag.ror(b ^ c, 12_u8)
        a = (a + y) + b
        d = Swag.ror(d ^ a, 8_u8)
        c += d
        b = Swag.ror(b ^ c, 7_u8)
    }

    const Left   = cast(Blake2sVector, [1, 2, 3, 0])
    const Across = cast(Blake2sVector, [2, 3, 0, 1])
    const Right  = cast(Blake2sVector, [3, 0, 1, 2])

    #[Swag.Inline]
    func gatherWords(message: const [*] u32, indexes: const [*] u8)->Blake2sVector
    {
        return cast(Blake2sVector, [message[indexes[0]], message[indexes[2]], message[indexes[4]], message[indexes[6]]])
    }

    for round in 10
    {
        let schedule = Blake2sSigma.buffer + round * 16
        mix(gatherWords(message, schedule), gatherWords(message, schedule + 1))
        b = Swag.vecShuffle(b, Left)
        c = Swag.vecShuffle(c, Across)
        d = Swag.vecShuffle(d, Right)
        mix(gatherWords(message, schedule + 8), gatherWords(message, schedule + 9))
        b = Swag.vecShuffle(b, Right)
        c = Swag.vecShuffle(c, Across)
        d = Swag.vecShuffle(d, Left)
    }

    state[][0] = a
    state[][1] = b
    state[][2] = c
    state[][3] = d
}

// Computes a BLAKE2s digest incrementally, in unkeyed or keyed mode.
//
// The digest size is selected when the sequence starts and bound into the state.
#[Swag.NoCopy, Swag.Opaque]
public struct Blake2s
{
    state:       [8] u32
    buffer:      [Blake2sBlockSize] u8
    bufferCount: u64
    counter:     u64
    digestSize:  u64
}

public impl Blake2s
{
    // Creates an unkeyed sequence producing `digestSize` bytes, from 1 to 32.
    func create(digestSize: u64)->Blake2s fail
    {
        var result: #returntype
        try result.reset(digestSize)
        return result
    }

    // Creates a keyed sequence producing `digestSize` bytes, from 1 to 32.
    //
    // `key` holds at most 32 bytes.
    func createKeyed(key: const [..] u8, digestSize: u64)->Blake2s fail
    {
        var result: #returntype
        try result.resetKeyed(key, digestSize)
        return result
    }

    // Replaces any previous state and starts a new unkeyed sequence.
    mtd reset(digestSize: u64) fail
    {
        try .resetKeyed("", digestSize)
    }

    // Replaces any previous state and starts a keyed sequence. `key` holds at most 32 bytes.
    mtd resetKeyed(key: const [..] u8, digestSize: u64) fail
    {
        if not digestSize or digestSize > Blake2sMaxDigestSize
        {
            fail Errors.BadParameterError{"BLAKE2s needs a digest length of 1 to 32 bytes"}
        }

        if key.count > Blake2sMaxKeySize
        {
            fail Errors.BadParameterError{"BLAKE2s accepts a key of at most 32 bytes"}
        }

        .clear()
        .state      = Blake2sIv
        .digestSize = digestSize
        .state[0]   ^= 0x0101_0000 ^ (cast(u32, key.count) << 8) ^ cast(u32, digestSize)

        if key.count
        {
            var keyBlock: [Blake2sBlockSize] u8
            Swag.memcpy(&keyBlock[0], key.buffer, key.count)
            .update(keyBlock)
            Crypto.secureClear(keyBlock)
        }
    }

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.digestSize != 0, "BLAKE2s needs an initialized sequence")
        var offset = 0_u64
        while offset < data.count
        {
            if .bufferCount == Blake2sBlockSize
            {
                .compress(&.buffer[0], .bufferCount, false)
                .bufferCount = 0
            }

            if .bufferCount == 0 and data.count - offset > Blake2sBlockSize
            {
                .compress(data.buffer + offset, Blake2sBlockSize, false)
                offset += Blake2sBlockSize
                continue
            }

            let count = Math.min(data.count - offset, Blake2sBlockSize - .bufferCount)
            Swag.memcpy(&.buffer[.bufferCount], data.buffer + offset, count)
            .bufferCount += count
            offset       += count
        }
    }

    // Finalizes the sequence into a destination of the configured digest length and clears state.
    mtd finalize(destination: [..] u8) fail
    {
        if not .digestSize
        {
            fail Errors.BadParameterError{"BLAKE2s needs an initialized sequence"}
        }

        if destination.count != .digestSize
        {
            fail Errors.BadParameterError{"BLAKE2s destination must match the configured digest length"}
        }

        Swag.memset(.buffer.buffer + .bufferCount, 0, Blake2sBlockSize - .bufferCount)
        .compress(&.buffer[0], .bufferCount, true)

        #static if BIG_ENDIAN
        {
            var words: [8] u32
            for index in 8
            {
                words[index] = Math.nativeToLittleEndian(.state[index])
            }

            Swag.memcpy(destination.buffer, &words[0], .digestSize)
            Crypto.secureClear(words)
        }
        else
        {
            Swag.memcpy(destination.buffer, &.state[0], .digestSize)
        }

        .clear()
    }

    // Clears all state held by this value.
    mtd clear()
    {
        if not .digestSize
        {
            return
        }

        Crypto.secureClear(.state)
        Crypto.secureClear(.buffer)
        .bufferCount = 0
        .counter     = 0
        .digestSize  = 0
    }

    // Computes an unkeyed BLAKE2s digest in one operation.
    //
    // The digest size is `destination.count`, from 1 to 32.
    func compute(data: const [..] u8, destination: [..] u8) fail
    {
        var hash = try Blake2s.create(destination.count)
        hash.update(data)
        try hash.finalize(destination)
    }

    // Computes a keyed BLAKE2s digest in one operation.
    //
    // The digest size is `destination.count`, from 1 to 32, and `key` holds at most 32 bytes.
    func computeKeyed(key, data: const [..] u8, destination: [..] u8) fail
    {
        var hash = try Blake2s.createKeyed(key, destination.count)
        hash.update(data)
        try hash.finalize(destination)
    }

    private mtd compress(input: const [*] u8, count: u64, last: bool)
    {
        let words = cast(const [*] u32, input)
        #static if BIG_ENDIAN
        {
            var converted: [16] u32
            for index in 16
            {
                converted[index] = Math.littleEndianToNative(words[index])
            }

            .compressWords(converted.buffer, count, last)
            Crypto.secureClear(converted)
        }
        else
        {
            .compressWords(words, count, last)
        }
    }

    #[Swag.Inline]
    private mtd compressWords(message: const [*] u32, count: u64, last: bool)
    {
        using Math

        .counter += count
        let lastFlag = last ? Swag.U32.Max : 0
        let flags = cast(Blake2sVector, [cast(u32, .counter), cast(u32, .counter >> 32), lastFlag, 0])
        var work = [
            Simd.load(.state.buffer),
            Simd.load(.state.buffer + 4),
            Simd.load(Blake2sIv.buffer),
            Simd.load(Blake2sIv.buffer + 4) ^ flags]

        blake2sRounds(message, &work)
        Simd.store(.state.buffer, Simd.load(.state.buffer) ^ work[0] ^ work[2])
        Simd.store(.state.buffer + 4, Simd.load(.state.buffer + 4) ^ work[1] ^ work[3])
        Crypto.secureClear(work)
    }

    // Clears state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}

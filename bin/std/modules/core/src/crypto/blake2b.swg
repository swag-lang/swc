#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of one BLAKE2b input block.
public const Blake2bBlockSize = 128

// Largest digest BLAKE2b can produce, in bytes.
public const Blake2bMaxDigestSize = 64

// Largest key BLAKE2b accepts in keyed mode, in bytes.
public const Blake2bMaxKeySize = 64

// Initialization vector, identical to the SHA-512 one.
private const Iv: [8] u64 = [
    0x6A09E667F3BCC908, 0xBB67AE8584CAA73B, 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1,
    0x510E527FADE682D1, 0x9B05688C2B3E6C1F, 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179]

// Message-word schedule, twelve rounds of sixteen indices, stored flat.
private const Sigma: [192] u8 = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
    11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
    7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
    9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
    2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
    12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
    13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
    6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
    10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3]

#[Swag.Inline]
private func load64(data: const [*] u8)->u64
{
    return cast(u64) data[0] | (cast(u64) data[1] << 8) |
           (cast(u64) data[2] << 16) | (cast(u64) data[3] << 24) |
           (cast(u64) data[4] << 32) | (cast(u64) data[5] << 40) |
           (cast(u64) data[6] << 48) | (cast(u64) data[7] << 56)
}

#[Swag.Inline]
private func store64(data: [*] u8, value: u64)
{
    for i in 8 do
        data[i] = cast(u8) ((value >> cast(u32) (i * 8)) & 0xFF)
}

#[Swag.Inline]
private func mix(state: *[16] u64, a, b, c, d: u64, x, y: u64)
{
    state[][a] += state[][b] + x
    state[][d] = @ror(state[][d] ^ state[][a], 32'u8)
    state[][c] += state[][d]
    state[][b] = @ror(state[][b] ^ state[][c], 24'u8)
    state[][a] += state[][b] + y
    state[][d] = @ror(state[][d] ^ state[][a], 16'u8)
    state[][c] += state[][d]
    state[][b] = @ror(state[][b] ^ state[][c], 63'u8)
}

// Computes a BLAKE2b digest incrementally, in unkeyed or keyed mode.
//
// The digest length is chosen when the sequence starts and is bound into the
// first state word, so two lengths never share a prefix. Use [[Core.Hash.Blake2b.compute]]
// for a one-shot digest.
#[Swag.NoCopy]
#[Swag.Opaque]
public struct Blake2b
{
    public
    {
        internal
        state:       [8] u64
        buffer:      [Blake2bBlockSize] u8
        bufferCount: u64
        counterLow:  u64
        counterHigh: u64
        digestSize:  u64
    }
}

public impl Blake2b
{
    // Creates an unkeyed sequence producing `digestSize` bytes, from 1 to 64.
    func create(digestSize: u64)->Blake2b fail
    {
        var result: retval
        try result.reset(digestSize)
        return result
    }

    // Creates a keyed sequence producing `digestSize` bytes, from 1 to 64.
    //
    // `key` holds at most 64 bytes. A keyed sequence prepends one padded key
    // block, which is what separates it from hashing the key and the message.
    func createKeyed(key: const [..] u8, digestSize: u64)->Blake2b fail
    {
        var result: retval
        try result.resetKeyed(key, digestSize)
        return result
    }

    // Replaces any previous state and starts a new unkeyed sequence.
    mtd reset(digestSize: u64) fail
    {
        try .resetKeyed("", digestSize)
    }

    // Replaces any previous state and starts a new keyed sequence.
    mtd resetKeyed(key: const [..] u8, digestSize: u64) fail
    {
        if !digestSize or digestSize > Blake2bMaxDigestSize do
            fail Errors.BadParameterError{"BLAKE2b needs a digest length of 1 to 64 bytes"}
        if @countof(key) > Blake2bMaxKeySize do
            fail Errors.BadParameterError{"BLAKE2b accepts a key of at most 64 bytes"}

        .clear()
        .state      = Iv
        .digestSize = digestSize
        .state[0]   ^= 0x0101_0000 ^ (@countof(key) << 8) ^ digestSize

        // The key becomes one full padded block, so an empty key and a key of
        // zero bytes of payload can never collide.
        if @countof(key)
        {
            var keyBlock: [Blake2bBlockSize] u8
            @memcpy(&keyBlock[0], @dataof(key), @countof(key))
            .update(keyBlock)
            Crypto.secureClear(keyBlock)
        }
    }

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        var offset = 0'u64
        while offset < @countof(data)
        {
            // A full buffer is only compressed once more input is known to
            // follow, because the last block takes the finalization flag.
            if .bufferCount == Blake2bBlockSize
            {
                .compress(false)
                .bufferCount = 0
            }

            let count = Math.min(@countof(data) - offset, Blake2bBlockSize - .bufferCount)
            @memcpy(&.buffer[.bufferCount], @dataof(data) + offset, count)
            .bufferCount += count
            offset       += count
        }
    }

    // Finalizes the sequence into `destination` and clears all state.
    //
    // `destination` holds exactly the digest length the sequence was created
    // with. Call [[Core.Hash.Blake2b.reset]] before reusing this value.
    mtd finalize(destination: [..] u8) fail
    {
        if @countof(destination) != .digestSize do
            fail Errors.BadParameterError{"BLAKE2b needs a destination of the declared digest length"}

        @memset(&.buffer[.bufferCount], 0, Blake2bBlockSize - .bufferCount)
        .compress(true)

        var words: [Blake2bMaxDigestSize] u8
        for i in 8 do
            store64(&words[i * 8], .state[i])
        @memcpy(@dataof(destination), &words[0], .digestSize)
        Crypto.secureClear(words)
        .clear()
    }

    // Clears all state held by this value.
    mtd clear()
    {
        Crypto.secureClear(.state)
        Crypto.secureClear(.buffer)
        .bufferCount = 0
        .counterLow  = 0
        .counterHigh = 0
        .digestSize  = 0
    }

    // Clears state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Computes an unkeyed BLAKE2b digest of `data` in one operation.
    //
    // The digest length is `@countof(destination)`, from 1 to 64 bytes.
    func compute(data: const [..] u8, destination: [..] u8) fail
    {
        var hash = try Blake2b.create(@countof(destination))
        hash.update(data)
        try hash.finalize(destination)
    }

    // Computes a keyed BLAKE2b digest of `data` in one operation.
    //
    // The digest length is `@countof(destination)`, from 1 to 64 bytes.
    func computeKeyed(key, data: const [..] u8, destination: [..] u8) fail
    {
        var hash = try Blake2b.createKeyed(key, @countof(destination))
        hash.update(data)
        try hash.finalize(destination)
    }

    private mtd compress(last: bool)
    {
        .counterLow += .bufferCount
        if .counterLow < .bufferCount do
            .counterHigh += 1

        var m: [16] u64
        for i in 16 do
            m[i] = load64(&.buffer[i * 8])

        var v: [16] u64
        for i in 8
        {
            v[i]     = .state[i]
            v[8 + i] = Iv[i]
        }

        v[12] ^= .counterLow
        v[13] ^= .counterHigh
        if last do
            v[14] ^= 0xFFFF_FFFF_FFFF_FFFF

        for round in 12
        {
            let s = round * 16
            mix(&v, 0, 4, 8, 12, m[Sigma[s + 0]], m[Sigma[s + 1]])
            mix(&v, 1, 5, 9, 13, m[Sigma[s + 2]], m[Sigma[s + 3]])
            mix(&v, 2, 6, 10, 14, m[Sigma[s + 4]], m[Sigma[s + 5]])
            mix(&v, 3, 7, 11, 15, m[Sigma[s + 6]], m[Sigma[s + 7]])
            mix(&v, 0, 5, 10, 15, m[Sigma[s + 8]], m[Sigma[s + 9]])
            mix(&v, 1, 6, 11, 12, m[Sigma[s + 10]], m[Sigma[s + 11]])
            mix(&v, 2, 7, 8, 13, m[Sigma[s + 12]], m[Sigma[s + 13]])
            mix(&v, 3, 4, 9, 14, m[Sigma[s + 14]], m[Sigma[s + 15]])
        }

        for i in 8 do
            .state[i] ^= v[i] ^ v[8 + i]

        Crypto.secureClear(m)
        Crypto.secureClear(v)
    }
}

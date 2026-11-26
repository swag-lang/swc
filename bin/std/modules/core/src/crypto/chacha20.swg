#global public
#global namespace Crypto

using Math

// Size in bytes of a ChaCha20 key.
const ChaCha20KeySize = 32

// Size in bytes of an IETF ChaCha20 nonce.
const ChaCha20NonceSize = 12

// Size in bytes of one ChaCha20 key-stream block.
const ChaCha20BlockSize = 64

// Reads a little-endian word without assuming byte-buffer alignment.
#[Swag.Inline]
private func load32(data: const [*] u8)->u32
{
    var value: u32
    Memory.copy(cast([*] void, &value), cast(const [*] void, data), #sizeof(value))
    return Math.littleEndianToNative(value)
}

private const ChaChaConstants = cast(Simd.U32x4, [0x61707865'u32, 0x3320646E, 0x79622D32, 0x6B206574])

#[Swag.Inline]
private func swapWordBytesOnBigEndian(bytes: Simd.U8x16)->Simd.U8x16
{
    #static if BIG_ENDIAN
    {
        const order = cast(Simd.U8x16, [3'u8, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12])
        return Simd.permute(bytes, order)
    }
    else
    {
        return bytes
    }
}

#[Swag.Inline]
private func rotate32By16(value: Simd.U32x4)->Simd.U32x4
{
    #static if BIG_ENDIAN
    {
        return Math.rol(value, 16)
    }
    else
    {
        const order = cast(Simd.U8x16, [2'u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
        return cast #bit (Simd.U32x4, Simd.permute(cast #bit (Simd.U8x16, value), order))
    }
}

// Operates on the four vector registers a, b, c and d at the call site.
#[Swag.Mixin]
private func quarterRoundLanes()
{
    a += b
    d = rotate32By16(d ^ a)
    c += d
    b = Math.rol(b ^ c, 12)
    a += b
    d = Math.rol(d ^ a, 8)
    c += d
    b = Math.rol(b ^ c, 7)
}

#[Swag.Inline]
private func quarterRound(first, second, third, fourth: *Simd.U32x4)
{
    var a = first[]
    var b = second[]
    var c = third[]
    var d = fourth[]

    quarterRoundLanes()

    first[]  = a
    second[] = b
    third[]  = c
    fourth[] = d
}

#[Swag.Inline]
private func roundRows(rows: *[4] Simd.U32x4)
{
    const left1 = cast(Simd.U32x4, [1'u32, 2, 3, 0])
    const left2 = cast(Simd.U32x4, [2'u32, 3, 0, 1])
    const left3 = cast(Simd.U32x4, [3'u32, 0, 1, 2])
    var a = rows[][0]
    var b = rows[][1]
    var c = rows[][2]
    var d = rows[][3]
    for 10
    {
        quarterRoundLanes()

        // Rotate the rows so each lane sees one diagonal, then restore the column order.
        b = Simd.permute(b, left1)
        c = Simd.permute(c, left2)
        d = Simd.permute(d, left3)
        quarterRoundLanes()
        b = Simd.permute(b, left3)
        c = Simd.permute(c, left2)
        d = Simd.permute(d, left1)
    }

    rows[][0] = a
    rows[][1] = b
    rows[][2] = c
    rows[][3] = d
}

// Produces one IETF ChaCha20 key-stream block for `counter`.
//
// Fails with [[Core.Errors.BadParameterError]] when `key` does not hold 32 bytes or `nonce` 12.
func chacha20Block(key: const [..] u8, counter: u32, nonce: const [..] u8)->[ChaCha20BlockSize] u8 fail
{
    if key.count != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if nonce.count != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}

    var initial: [4] Simd.U32x4
    initial[0] = ChaChaConstants
    initial[1] = cast #bit (Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key.buffer)))
    initial[2] = cast #bit (Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key.buffer + 16)))
    initial[3] = cast(Simd.U32x4,
                      [counter, load32(nonce.buffer), load32(nonce.buffer + 4), load32(nonce.buffer + 8)])

    var state = initial
    roundRows(&state)

    var result: #returntype
    for i in 4
    {
        let words = cast #bit (Simd.U8x16, state[i] + initial[i])
        Simd.store(result.buffer + i * #sizeof(Simd.U8x16), swapWordBytesOnBigEndian(words))
    }

    secureClear(initial)
    secureClear(state)
    return result
}

// Derives the XChaCha20 subkey from a 32-byte key and the first 16 nonce bytes.
internal func hchacha20(key: const [..] u8, nonce: const [..] u8)->[ChaCha20KeySize] u8 fail
{
    if key.count != ChaCha20KeySize do
        fail Errors.BadParameterError{"HChaCha20 needs a 32-byte key"}
    if nonce.count != 16 do
        fail Errors.BadParameterError{"HChaCha20 needs a 16-byte nonce"}

    var state: [4] Simd.U32x4
    state[0] = ChaChaConstants
    state[1] = cast #bit (Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key.buffer)))
    state[2] = cast #bit (Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key.buffer + 16)))
    state[3] = cast #bit (Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(nonce.buffer)))
    roundRows(&state)

    var subkey: #returntype
    Simd.store(subkey.buffer, swapWordBytesOnBigEndian(cast #bit (Simd.U8x16, state[0])))
    Simd.store(subkey.buffer + 16, swapWordBytesOnBigEndian(cast #bit (Simd.U8x16, state[3])))
    secureClear(state)
    return subkey
}

// XORs `source` with the IETF ChaCha20 key stream into `destination`.
//
// The first block uses the key-stream counter `initialCounter`. Source and destination can be
// the same slice; other overlapping ranges are not supported. Large inputs share the runtime
// worker pool, and all output is complete before the call returns.
//
// Fails with [[Core.Errors.BadParameterError]] when `key` does not hold 32 bytes, `nonce` 12,
// or `destination` as many bytes as `source`, and with [[Core.Errors.OverflowError]] when the
// input needs more blocks than the counter range starting at `initialCounter` provides.
func chacha20Xor(key, nonce, source: const [..] u8, destination: [..] u8, initialCounter = 0'u32) fail
{
    func chacha20XorBatches(key, nonce: const [..] u8, counter: u32, source: const [*] u8, destination: [*] u8, count: u64)
    {
        var initial: [16] Simd.U32x4
        initial[0] = Simd.splat(0x61707865'u32)
        initial[1] = Simd.splat(0x3320646E'u32)
        initial[2] = Simd.splat(0x79622D32'u32)
        initial[3] = Simd.splat(0x6B206574'u32)
        for i in 8 do
            initial[4 + i] = Simd.splat(load32(key.buffer + i * 4))
        initial[13] = Simd.splat(load32(nonce.buffer))
        initial[14] = Simd.splat(load32(nonce.buffer + 4))
        initial[15] = Simd.splat(load32(nonce.buffer + 8))

        const counterOffsets = cast(Simd.U32x4, [0'u32, 1, 2, 3])
        var state: [16] Simd.U32x4
        var words: [4] Simd.U32x4
        for batch in count
        {
            initial[12] = Simd.splat(counter + cast(u32, (batch * 4))) + counterOffsets
            state = initial
            for 10
            {
                quarterRound(&state[0], &state[4], &state[8], &state[12])
                quarterRound(&state[1], &state[5], &state[9], &state[13])
                quarterRound(&state[2], &state[6], &state[10], &state[14])
                quarterRound(&state[3], &state[7], &state[11], &state[15])
                quarterRound(&state[0], &state[5], &state[10], &state[15])
                quarterRound(&state[1], &state[6], &state[11], &state[12])
                quarterRound(&state[2], &state[7], &state[8], &state[13])
                quarterRound(&state[3], &state[4], &state[9], &state[14])
            }

            // Transpose each four-word group from lanes of independent blocks into
            // consecutive words, so it can be applied directly to the input.
            for group in 4
            {
                for word in 4 do
                    words[word] = state[group * 4 + word] + initial[group * 4 + word]
                Simd.transpose4x4(&words)
                for block in 4
                {
                    let offset = (batch * 4 + block) * ChaCha20BlockSize + group * #sizeof(Simd.U8x16)
                    let stream = swapWordBytesOnBigEndian(cast #bit (Simd.U8x16, words[block]))
                    Simd.store(destination + offset, Simd.load(source + offset) ^ stream)
                }
            }
        }

        secureClear(initial)
        secureClear(state)
        secureClear(words)
    }

    if key.count != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if nonce.count != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    if source.count != destination.count do
        fail Errors.BadParameterError{"ChaCha20 source and destination need the same length"}

    let blockCount = source.count ? ((source.count - 1) / ChaCha20BlockSize) + 1 : 0
    if blockCount and blockCount - 1 > Swag.U32.Max - initialCounter do
        fail Errors.OverflowError{"ChaCha20 input exceeds the counter range"}

    const BatchesPerChunk = 16
    const BatchSize = 4 * ChaCha20BlockSize
    let batches = source.count / BatchSize
    let chunks = (batches + BatchesPerChunk - 1) / BatchesPerChunk

    // A chunk reuses its initial state and scratch for several complete batches.
    // Chunks own disjoint ranges, so exact in-place XOR remains valid.
    if batches == 1 do
        chacha20XorBatches(key, nonce, initialCounter, source.buffer, destination.buffer, 1)
    elif batches
    {
        parallel for |&key, &nonce, &source, &destination, initialCounter, batches| chunk in chunks
        {
            let first = chunk * BatchesPerChunk
            let count = Math.min(batches - first, BatchesPerChunk)
            let start = first * BatchSize
            let counter = initialCounter + cast(u32, (first * 4))
            chacha20XorBatches(key, nonce, counter, source.buffer + start, destination.buffer + start, count)
        }
    }

    var offset  = batches * BatchSize
    var counter = initialCounter

    // The last legal counter need not have a successor when there is no tail.
    if offset < source.count do
        counter += cast(u32, (batches * 4))

    while offset < source.count
    {
        var block = try chacha20Block(key, counter, nonce)
        let count = Math.min(source.count - offset, ChaCha20BlockSize)

        // Apply complete vectors first, then finish the last partial vector by bytes.
        let src = source.buffer + offset
        let dst = destination.buffer + offset
        var i   = 0'u64
        while count - i >= #sizeof(Simd.U8x16)
        {
            Simd.store(dst + i, Simd.load(src + i) ^ Simd.load(block.buffer + i))
            i += #sizeof(Simd.U8x16)
        }

        while i < count
        {
            dst[i] = src[i] ^ block[i]
            i      += 1
        }

        secureClear(block)
        offset += count
        if offset < source.count do
            counter += 1
    }
}

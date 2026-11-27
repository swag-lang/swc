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

private const ChaChaConstants = cast(Simd.U32x4, [0x61707865_u32, 0x3320646E, 0x79622D32, 0x6B206574])

#[Swag.Inline]
private func swapWordBytesOnBigEndian(bytes: Simd.U8x16)->Simd.U8x16
{
    #static if BIG_ENDIAN
    {
        const order = cast(Simd.U8x16, [3_u8, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12])
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
        const order = cast(Simd.U8x16, [2_u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
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
private func roundRows(rows: *[4] Simd.U32x4)
{
    const left1 = cast(Simd.U32x4, [1_u32, 2, 3, 0])
    const left2 = cast(Simd.U32x4, [2_u32, 3, 0, 1])
    const left3 = cast(Simd.U32x4, [3_u32, 0, 1, 2])
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

#[Swag.Inline]
private func loadChaChaKeyRows(key: const [*] u8, rows: *[4] Simd.U32x4)
{
    rows[][0] = ChaChaConstants
    rows[][1] = cast #bit(Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key)))
    rows[][2] = cast #bit(Simd.U32x4, swapWordBytesOnBigEndian(Simd.load(key + 16)))
}

// Produces one IETF ChaCha20 key-stream block for `counter`.
//
// Fails with [[Core.Errors.BadParameterError]] when `key` does not hold 32 bytes or `nonce` 12.
func chacha20Block(key: const [..] u8, counter: u32, nonce: const [..] u8)->[ChaCha20BlockSize] u8 fail
{
    if key.count != ChaCha20KeySize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    }

    if nonce.count != ChaCha20NonceSize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    }

    var initial: [4] Simd.U32x4
    loadChaChaKeyRows(key.buffer, &initial)
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
    if key.count != ChaCha20KeySize
    {
        fail Errors.BadParameterError{"HChaCha20 needs a 32-byte key"}
    }

    if nonce.count != 16
    {
        fail Errors.BadParameterError{"HChaCha20 needs a 16-byte nonce"}
    }

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

#[Swag.Mixin]
private func quarterRoundPair()
{
    a += b
    e += f
    d = rotate32By16(d ^ a)
    h = rotate32By16(h ^ e)
    c += d
    g += h
    b = Math.rol(b ^ c, 12)
    f = Math.rol(f ^ g, 12)
    a += b
    e += f
    d = Math.rol(d ^ a, 8)
    h = Math.rol(h ^ e, 8)
    c += d
    g += h
    b = Math.rol(b ^ c, 7)
    f = Math.rol(f ^ g, 7)
}

#[Swag.Inline]
private func roundRowsPair(zero, first: *[4] Simd.U32x4)
{
    const left1 = cast(Simd.U32x4, [1_u32, 2, 3, 0])
    const left2 = cast(Simd.U32x4, [2_u32, 3, 0, 1])
    const left3 = cast(Simd.U32x4, [3_u32, 0, 1, 2])
    var a = zero[][0]
    var b = zero[][1]
    var c = zero[][2]
    var d = zero[][3]
    var e = first[][0]
    var f = first[][1]
    var g = first[][2]
    var h = first[][3]
    for 10
    {
        quarterRoundPair()
        b = Simd.permute(b, left1)
        c = Simd.permute(c, left2)
        d = Simd.permute(d, left3)
        f = Simd.permute(f, left1)
        g = Simd.permute(g, left2)
        h = Simd.permute(h, left3)
        quarterRoundPair()
        b = Simd.permute(b, left3)
        c = Simd.permute(c, left2)
        d = Simd.permute(d, left1)
        f = Simd.permute(f, left3)
        g = Simd.permute(g, left2)
        h = Simd.permute(h, left1)
    }
    zero[][0] = a
    zero[][1] = b
    zero[][2] = c
    zero[][3] = d
    first[][0] = e
    first[][1] = f
    first[][2] = g
    first[][3] = h
}

// Produces the Poly1305 key and one block of ciphertext for a short AEAD message.
internal func chacha20SealShort(key, nonce, plaintext: const [..] u8, ciphertext: [..] u8,
                                authKey: *[Poly1305KeySize] u8) fail
{
    if key.count != ChaCha20KeySize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    }
    if nonce.count != ChaCha20NonceSize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    }

    var scratch: struct
    {
        initial, zero, first: [4] Simd.U32x4
        tail: [16] u8
    }

    with scratch
    {
        loadChaChaKeyRows(key.buffer, &.initial)
        .initial[3] = cast(Simd.U32x4, [0_u32, load32(nonce.buffer), load32(nonce.buffer + 4), load32(nonce.buffer + 8)])
        let counterStep = cast(Simd.U32x4, [1_u32, 0, 0, 0])
        .zero     = .initial
        .first    = .initial
        .first[3] += counterStep
        roundRowsPair(&.zero, &.first)
        .first[3] += counterStep

        for row in Poly1305KeySize / #sizeof(Simd.U8x16)
        {
            let stream = swapWordBytesOnBigEndian(cast #bit(Simd.U8x16, .zero[row] + .initial[row]))
            Simd.store(authKey[].buffer + row * #sizeof(Simd.U8x16), stream)
        }
        let rowCount = plaintext.count / #sizeof(Simd.U8x16)
        for row in rowCount
        {
            let offset = row * #sizeof(Simd.U8x16)
            let stream = swapWordBytesOnBigEndian(cast #bit(Simd.U8x16, .first[row] + .initial[row]))
            Simd.store(ciphertext.buffer + offset, Simd.load(plaintext.buffer + offset) ^ stream)
        }
        let remaining = plaintext.count % #sizeof(Simd.U8x16)
        if remaining
        {
            let offset = rowCount * #sizeof(Simd.U8x16)
            let stream = swapWordBytesOnBigEndian(cast #bit(Simd.U8x16, .first[rowCount] + .initial[rowCount]))
            Simd.store(.tail.buffer, stream)
            for byte in remaining
            {
                ciphertext.buffer[offset + byte] = plaintext.buffer[offset + byte] ^ .tail[byte]
            }
        }
    }
    secureClear(Swag.makeSlice(&scratch, 1))
}

#[Swag.Inline]
private func xorRows(initial, state: const *[4] Simd.U32x4, source: const [*] u8, destination: [*] u8,
                          length: u64, tail: *[16] u8)
{
    let rowCount = length / #sizeof(Simd.U8x16)
    for row in rowCount
    {
        let offset = row * #sizeof(Simd.U8x16)
        let stream = swapWordBytesOnBigEndian(cast #bit(Simd.U8x16, state[][row] + initial[][row]))
        Simd.store(destination + offset, Simd.load(source + offset) ^ stream)
    }

    let remaining = length % #sizeof(Simd.U8x16)
    if remaining
    {
        let offset = rowCount * #sizeof(Simd.U8x16)
        let stream = swapWordBytesOnBigEndian(cast #bit(Simd.U8x16, state[][rowCount] + initial[][rowCount]))
        Simd.store(tail[].buffer, stream)
        for byte in remaining
        {
            destination[offset + byte] = source[offset + byte] ^ tail[][byte]
        }
    }
}

private func chacha20XorTail(key, nonce, source: const [*] u8, destination: [*] u8, length: u64, counter: u32)
{
    var scratch: struct
    {
        initial, state: [4] Simd.U32x4
        tail: [16] u8
    }

    with scratch
    {
        loadChaChaKeyRows(key, &.initial)
        .initial[3] = cast(Simd.U32x4, [counter, load32(nonce), load32(nonce + 4), load32(nonce + 8)])
        .state = .initial
        roundRows(&.state)
        xorRows(&.initial, &.state, source, destination, length, &.tail)
    }

    secureClear(Swag.makeSlice(&scratch, 1))
}

private func chacha20XorTailPairs(key, nonce, source: const [*] u8, destination: [*] u8,
                              length: u64, counter: u32)
{
    var scratch: struct
    {
        initial, first, second: [4] Simd.U32x4
        tail: [16] u8
    }

    with scratch
    {
        loadChaChaKeyRows(key, &.initial)
        const CounterStep = cast(Simd.U32x4, [1_u32, 0, 0, 0])
        var lastRow: [4] u32 = [counter, load32(nonce), load32(nonce + 4), load32(nonce + 8)]
        var offset = 0_u64
        while length - offset > ChaCha20BlockSize
        {
            .initial[3] = cast(Simd.U32x4, lastRow)
            .first = .initial
            .second = .initial
            .second[3] += CounterStep
            roundRowsPair(&.first, &.second)
            .second[3] += CounterStep

            xorRows(&.initial, &.first, source + offset, destination + offset, ChaCha20BlockSize, &.tail)
            offset += ChaCha20BlockSize
            let count = Math.min(length - offset, ChaCha20BlockSize)
            xorRows(&.initial, &.second, source + offset, destination + offset, count, &.tail)
            offset += count
            if offset < length
            {
                lastRow[0] += 2
            }
        }

        if offset < length
        {
            .initial[3] = cast(Simd.U32x4, lastRow)
            .first = .initial
            roundRows(&.first)
            xorRows(&.initial, &.first, source + offset, destination + offset, length - offset, &.tail)
        }
    }

    secureClear(Swag.makeSlice(&scratch, 1))
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
func chacha20Xor(key, nonce, source: const [..] u8, destination: [..] u8, initialCounter = 0_u32) fail
{
    func chacha20XorBatches(key, nonce: const [..] u8, counter: u32, source: const [*] u8, destination: [*] u8, count: u64)
    {
        // Interleave arithmetic from four independent quarter rounds.
        #[Swag.Mixin]
        func quarterRoundColumns(a0, b0, c0, d0, a1, b1, c1, d1,
                                 a2, b2, c2, d2, a3, b3, c3, d3: *Simd.U32x4)
        {
            a0[] += b0[]
            a1[] += b1[]
            a2[] += b2[]
            a3[] += b3[]

            d0[] = rotate32By16(d0[] ^ a0[])
            d1[] = rotate32By16(d1[] ^ a1[])
            d2[] = rotate32By16(d2[] ^ a2[])
            d3[] = rotate32By16(d3[] ^ a3[])

            c0[] += d0[]
            c1[] += d1[]
            c2[] += d2[]
            c3[] += d3[]

            b0[] = Math.rol(b0[] ^ c0[], 12)
            b1[] = Math.rol(b1[] ^ c1[], 12)
            b2[] = Math.rol(b2[] ^ c2[], 12)
            b3[] = Math.rol(b3[] ^ c3[], 12)

            a0[] += b0[]
            a1[] += b1[]
            a2[] += b2[]
            a3[] += b3[]

            d0[] = Math.rol(d0[] ^ a0[], 8)
            d1[] = Math.rol(d1[] ^ a1[], 8)
            d2[] = Math.rol(d2[] ^ a2[], 8)
            d3[] = Math.rol(d3[] ^ a3[], 8)

            c0[] += d0[]
            c1[] += d1[]
            c2[] += d2[]
            c3[] += d3[]

            b0[] = Math.rol(b0[] ^ c0[], 7)
            b1[] = Math.rol(b1[] ^ c1[], 7)
            b2[] = Math.rol(b2[] ^ c2[], 7)
            b3[] = Math.rol(b3[] ^ c3[], 7)
        }

        var initial: [16] Simd.U32x4
        initial[0] = Simd.splat(0x61707865_u32)
        initial[1] = Simd.splat(0x3320646E_u32)
        initial[2] = Simd.splat(0x79622D32_u32)
        initial[3] = Simd.splat(0x6B206574_u32)
        for i in 8
        {
            initial[4 + i] = Simd.splat(load32(key.buffer + i * 4))
        }

        initial[13] = Simd.splat(load32(nonce.buffer))
        initial[14] = Simd.splat(load32(nonce.buffer + 4))
        initial[15] = Simd.splat(load32(nonce.buffer + 8))

        const counterOffsets = cast(Simd.U32x4, [0_u32, 1, 2, 3])
        var state: [16] Simd.U32x4
        var words: [4] Simd.U32x4
        for batch in count
        {
            initial[12] = Simd.splat(counter + cast(u32, (batch * 4))) + counterOffsets
            var a0 = initial[0]
            var a1 = initial[1]
            var a2 = initial[2]
            var a3 = initial[3]
            var b0 = initial[4]
            var b1 = initial[5]
            var b2 = initial[6]
            var b3 = initial[7]
            var c0 = initial[8]
            var c1 = initial[9]
            var c2 = initial[10]
            var c3 = initial[11]
            var d0 = initial[12]
            var d1 = initial[13]
            var d2 = initial[14]
            var d3 = initial[15]

            for 10
            {
                quarterRoundColumns(&a0, &b0, &c0, &d0,
                                    &a1, &b1, &c1, &d1,
                                    &a2, &b2, &c2, &d2,
                                    &a3, &b3, &c3, &d3)

                quarterRoundColumns(&a0, &b1, &c2, &d3,
                                    &a1, &b2, &c3, &d0,
                                    &a2, &b3, &c0, &d1,
                                    &a3, &b0, &c1, &d2)
            }

            state[0] = a0
            state[1] = a1
            state[2] = a2
            state[3] = a3
            state[4] = b0
            state[5] = b1
            state[6] = b2
            state[7] = b3
            state[8] = c0
            state[9] = c1
            state[10] = c2
            state[11] = c3
            state[12] = d0
            state[13] = d1
            state[14] = d2
            state[15] = d3

            // Transpose each four-word group from lanes of independent blocks into
            // consecutive words, so it can be applied directly to the input.
            for group in 4
            {
                for word in 4
                {
                    words[word] = state[group * 4 + word] + initial[group * 4 + word]
                }

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

    if key.count != ChaCha20KeySize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    }

    if nonce.count != ChaCha20NonceSize
    {
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    }

    if source.count != destination.count
    {
        fail Errors.BadParameterError{"ChaCha20 source and destination need the same length"}
    }

    let blockCount = source.count ? ((source.count - 1) / ChaCha20BlockSize) + 1 : 0
    if blockCount and blockCount - 1 > Swag.U32.Max - initialCounter
    {
        fail Errors.OverflowError{"ChaCha20 input exceeds the counter range"}
    }

    const BatchesPerChunk = 16
    const BatchSize       = 4 * ChaCha20BlockSize
    let batches = source.count / BatchSize
    let chunks  = (batches + BatchesPerChunk - 1) / BatchesPerChunk

    // A chunk reuses its initial state and scratch for several complete batches.
    // Chunks own disjoint ranges, so exact in-place XOR remains valid.
    if batches == 1
    {
        chacha20XorBatches(key, nonce, initialCounter, source.buffer, destination.buffer, 1)
    }
    else if batches
    {
        parallel for |&key, &nonce, &source, &destination, initialCounter, batches| chunk in chunks
        {
            let first   = chunk * BatchesPerChunk
            let count   = Math.min(batches - first, BatchesPerChunk)
            let start   = first * BatchSize
            let counter = initialCounter + cast(u32, (first * 4))
            chacha20XorBatches(key, nonce, counter, source.buffer + start, destination.buffer + start, count)
        }
    }

    let offset = batches * BatchSize

    // The last legal counter need not have a successor when there is no tail.
    if offset < source.count
    {
        let counter = initialCounter + cast(u32, (batches * 4))
        let length  = source.count - offset
        if length > ChaCha20BlockSize
        {
            chacha20XorTailPairs(key.buffer, nonce.buffer, source.buffer + offset, destination.buffer + offset, length, counter)
        }
        else
        {
            chacha20XorTail(key.buffer, nonce.buffer, source.buffer + offset, destination.buffer + offset, length, counter)
        }
    }
}

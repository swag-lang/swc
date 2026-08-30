#global public
#global namespace Crypto

// Size in bytes of a ChaCha20 key.
const ChaCha20KeySize = 32

// Size in bytes of an IETF ChaCha20 nonce.
const ChaCha20NonceSize = 12

// Size in bytes of one ChaCha20 key-stream block.
const ChaCha20BlockSize = 64

#[Swag.Inline]
private func add32(left, right: u32)->u32 => cast(u32) ((cast(u64) left + right) & 0xFFFF_FFFF)

// The wire format is little-endian, which is the target's byte order: one
// unaligned word access replaces the byte-at-a-time assembly.
#[Swag.Inline]
private func load32(data: const [*] u8)->u32 => data[as u32]

#[Swag.Inline]
private func store32(data: [*] u8, value: u32)
{
    data[as u32] = value
}

#[Swag.Inline]
private func quarterRound(state: *[16] u32, a, b, c, d: u32)
{
    state[][a] = add32(state[][a], state[][b])
    state[][d] ^= state[][a]
    state[][d] = Swag.rol(state[][d], 16)
    state[][c] = add32(state[][c], state[][d])
    state[][b] ^= state[][c]
    state[][b] = Swag.rol(state[][b], 12)
    state[][a] = add32(state[][a], state[][b])
    state[][d] ^= state[][a]
    state[][d] = Swag.rol(state[][d], 8)
    state[][c] = add32(state[][c], state[][d])
    state[][b] ^= state[][c]
    state[][b] = Swag.rol(state[][b], 7)
}

#[Swag.Inline]
private func rotate32(value: Math.Simd.U32x4, bits: u8)->Math.Simd.U32x4 => (value << bits) | (value >> (32 - bits))

#[Swag.Inline]
private func quarterRound4(state: *[16] Math.Simd.U32x4, a, b, c, d: u32)
{
    state[][a] += state[][b]
    state[][d] ^= state[][a]
    state[][d] = rotate32(state[][d], 16)
    state[][c] += state[][d]
    state[][b] ^= state[][c]
    state[][b] = rotate32(state[][b], 12)
    state[][a] += state[][b]
    state[][d] ^= state[][a]
    state[][d] = rotate32(state[][d], 8)
    state[][c] += state[][d]
    state[][b] ^= state[][c]
    state[][b] = rotate32(state[][b], 7)
}

private func chacha20XorFour(key, nonce: const [..] u8, counter: u32, source: const [*] u8, destination: [*] u8)
{
    var initial: [16] Math.Simd.U32x4
    initial[0] = Math.Simd.splat(0x61707865'u32)
    initial[1] = Math.Simd.splat(0x3320646E'u32)
    initial[2] = Math.Simd.splat(0x79622D32'u32)
    initial[3] = Math.Simd.splat(0x6B206574'u32)
    for i in 8 do
        initial[4 + i] = Math.Simd.splat(load32(key.buffer + i * 4))
    initial[12] = cast(Math.Simd.U32x4) [counter, counter + 1, counter + 2, counter + 3]
    initial[13] = Math.Simd.splat(load32(nonce.buffer))
    initial[14] = Math.Simd.splat(load32(nonce.buffer + 4))
    initial[15] = Math.Simd.splat(load32(nonce.buffer + 8))

    var state = initial
    for round in 10
    {
        discard round
        quarterRound4(&state, 0, 4, 8, 12)
        quarterRound4(&state, 1, 5, 9, 13)
        quarterRound4(&state, 2, 6, 10, 14)
        quarterRound4(&state, 3, 7, 11, 15)
        quarterRound4(&state, 0, 5, 10, 15)
        quarterRound4(&state, 1, 6, 11, 12)
        quarterRound4(&state, 2, 7, 8, 13)
        quarterRound4(&state, 3, 4, 9, 14)
    }

    var stream: [4 * ChaCha20BlockSize] u8
    for word in 16
    {
        let value = state[word] + initial[word]
        for lane in 4
        {
            let offset = lane * ChaCha20BlockSize + word * 4
            store32(&stream[offset], value[lane])
        }
    }

    var offset = 0
    while offset < 4 * ChaCha20BlockSize
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) ^ Math.Simd.load(&stream[offset]))
        offset += #sizeof(Math.Simd.U8x16)
    }

    secureClear(initial)
    secureClear(state)
    secureClear(stream)
}

// Produces one IETF ChaCha20 key-stream block for `counter`.
func chacha20Block(key: const [..] u8, counter: u32, nonce: const [..] u8)->[ChaCha20BlockSize] u8 fail
{
    if key.count != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if nonce.count != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}

    var initial: [16] u32
    initial[0] = 0x61707865
    initial[1] = 0x3320646E
    initial[2] = 0x79622D32
    initial[3] = 0x6B206574
    for i in 8 do
        initial[4 + i] = load32(key.buffer + i * 4)
    initial[12] = counter
    initial[13] = load32(nonce.buffer)
    initial[14] = load32(nonce.buffer + 4)
    initial[15] = load32(nonce.buffer + 8)

    var state = initial
    for round in 10
    {
        discard round
        quarterRound(&state, 0, 4, 8, 12)
        quarterRound(&state, 1, 5, 9, 13)
        quarterRound(&state, 2, 6, 10, 14)
        quarterRound(&state, 3, 7, 11, 15)
        quarterRound(&state, 0, 5, 10, 15)
        quarterRound(&state, 1, 6, 11, 12)
        quarterRound(&state, 2, 7, 8, 13)
        quarterRound(&state, 3, 4, 9, 14)
    }

    var result: retval
    for i in 16 do
        store32(&result[i * 4], add32(state[i], initial[i]))
    secureClear(initial)
    secureClear(state)
    return result
}

// XORs `source` with the IETF ChaCha20 key stream into `destination`.
//
// Source and destination can be the same slice. Other overlapping ranges are not supported.
func chacha20Xor(key, nonce, source: const [..] u8, destination: [..] u8, initialCounter = 0'u32) fail
{
    if key.count != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if nonce.count != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    if source.count != destination.count do
        fail Errors.BadParameterError{"ChaCha20 source and destination need the same length"}

    let blockCount = source.count ? ((source.count - 1) / ChaCha20BlockSize) + 1 : 0
    if blockCount and blockCount - 1 > Swag.U32.Max - initialCounter do
        fail Errors.OverflowError{"ChaCha20 input exceeds the counter range"}

    var offset  = 0'u64
    var counter = initialCounter
    while source.count - offset >= 4 * ChaCha20BlockSize
    {
        chacha20XorFour(key, nonce, counter, source.buffer + offset, destination.buffer + offset)
        offset += 4 * ChaCha20BlockSize
        if offset < source.count do
            counter += 4
    }

    while offset < source.count
    {
        var block = chacha20Block(key, counter, nonce)
        let count = Math.min(source.count - offset, ChaCha20BlockSize)

        // Apply the key stream a word at a time; the tail of the final
        // partial block falls back to bytes.
        let src = source.buffer + offset
        let dst = destination.buffer + offset
        var i   = 0'u64
        while i + 8 <= count
        {
            (dst + i)[as u64] = (src + i)[as u64] ^ (&block[i])[as u64]
            i                 += 8
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

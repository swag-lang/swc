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
private func load32(data: const [*] u8)->u32 => dref cast(const *u32) data

#[Swag.Inline]
private func store32(data: [*] u8, value: u32)
{
    dref cast(*u32) data = value
}

#[Swag.Inline]
private func quarterRound(state: *[16] u32, a, b, c, d: u32)
{
    (dref state)[a] = add32((dref state)[a], (dref state)[b])
    (dref state)[d] ^= (dref state)[a]
    (dref state)[d] = @rol((dref state)[d], 16)
    (dref state)[c] = add32((dref state)[c], (dref state)[d])
    (dref state)[b] ^= (dref state)[c]
    (dref state)[b] = @rol((dref state)[b], 12)
    (dref state)[a] = add32((dref state)[a], (dref state)[b])
    (dref state)[d] ^= (dref state)[a]
    (dref state)[d] = @rol((dref state)[d], 8)
    (dref state)[c] = add32((dref state)[c], (dref state)[d])
    (dref state)[b] ^= (dref state)[c]
    (dref state)[b] = @rol((dref state)[b], 7)
}

// Produces one IETF ChaCha20 key-stream block for `counter`.
func chacha20Block(key: const [..] u8, counter: u32, nonce: const [..] u8)->[ChaCha20BlockSize] u8 fail
{
    if @countof(key) != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if @countof(nonce) != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}

    var initial: [16] u32
    initial[0] = 0x61707865
    initial[1] = 0x3320646E
    initial[2] = 0x79622D32
    initial[3] = 0x6B206574
    for i in 8 do
        initial[4 + i] = load32(@dataof(key) + i * 4)
    initial[12] = counter
    initial[13] = load32(@dataof(nonce))
    initial[14] = load32(@dataof(nonce) + 4)
    initial[15] = load32(@dataof(nonce) + 8)

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
    if @countof(key) != ChaCha20KeySize do
        fail Errors.BadParameterError{"ChaCha20 needs a 32-byte key"}
    if @countof(nonce) != ChaCha20NonceSize do
        fail Errors.BadParameterError{"ChaCha20 needs a 12-byte nonce"}
    if @countof(source) != @countof(destination) do
        fail Errors.BadParameterError{"ChaCha20 source and destination need the same length"}

    let blockCount = @countof(source) ? ((@countof(source) - 1) / ChaCha20BlockSize) + 1 : 0
    if blockCount and blockCount - 1 > Swag.U32.Max - initialCounter do
        fail Errors.OverflowError{"ChaCha20 input exceeds the counter range"}

    var offset  = 0'u64
    var counter = initialCounter
    while offset < @countof(source)
    {
        var block = chacha20Block(key, counter, nonce)
        let count = Math.min(@countof(source) - offset, ChaCha20BlockSize)

        // Apply the key stream a word at a time; the tail of the final
        // partial block falls back to bytes.
        let src = @dataof(source) + offset
        let dst = @dataof(destination) + offset
        var i   = 0'u64
        while i + 8 <= count
        {
            dref cast(*u64) (dst + i) = (dref cast(const *u64) (src + i)) ^ (dref cast(const *u64) &block[i])
            i += 8
        }

        while i < count
        {
            dst[i] = src[i] ^ block[i]
            i      += 1
        }

        secureClear(block)
        offset += count
        if offset < @countof(source) do
            counter += 1
    }
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func sameChaChaBytes(left, right: const [..] u8)->bool
{
    return left.count == right.count and
           Swag.memcmp(left.buffer, right.buffer, left.count) == 0
}

func testKey()->[Crypto.ChaCha20KeySize] u8
{
    var result: retval
    for i in Crypto.ChaCha20KeySize do
        result[i] = cast(u8) i
    return result
}

func testNonce()->[Crypto.ChaCha20NonceSize] u8
{
    return [0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x4A, 0x00, 0x00, 0x00, 0x00]
}

func scalarChaCha20Xor(key, nonce, source: const [..] u8, destination: [..] u8, initialCounter: u32)
{
    var offset  = 0'u64
    var counter = initialCounter
    while offset < source.count
    {
        let block = expect Crypto.chacha20Block(key, counter, nonce)
        let count = Math.min(source.count - offset, Crypto.ChaCha20BlockSize)
        for i in count do
            destination[offset + i] = source[offset + i] ^ block[i]
        offset += count
        if offset < source.count do
            counter += 1
    }
}

// RFC 8439 section 2.3.2.
#test
{
    let key   = testKey()
    let nonce = testNonce()
    let expected: [Crypto.ChaCha20BlockSize] u8 = [
        0x10, 0xF1, 0xE7, 0xE4, 0xD1, 0x3B, 0x59, 0x15,
        0x50, 0x0F, 0xDD, 0x1F, 0xA3, 0x20, 0x71, 0xC4,
        0xC7, 0xD1, 0xF4, 0xC7, 0x33, 0xC0, 0x68, 0x03,
        0x04, 0x22, 0xAA, 0x9A, 0xC3, 0xD4, 0x6C, 0x4E,
        0xD2, 0x82, 0x64, 0x46, 0x07, 0x9F, 0xAA, 0x09,
        0x14, 0xC2, 0xD7, 0x05, 0xD9, 0x8B, 0x02, 0xA2,
        0xB5, 0x12, 0x9C, 0xD1, 0xDE, 0x16, 0x4E, 0xB9,
        0xCB, 0xD0, 0x83, 0xE8, 0xA2, 0x50, 0x3C, 0x4E]

    let block = expect Crypto.chacha20Block(key, 1, nonce)
    Swag.assert(sameChaChaBytes(block, expected))
}

// Encryption is the key stream folded into the input, and folding it twice gives the input back.
// The length crosses a block boundary and ends inside one, so the partial trailing block is
// covered as well.
#test
{
    let key   = testKey()
    let nonce = testNonce()

    const Count = 137
    var data: [Count] u8
    for i in Count do
        data[i] = cast(u8) ((i * 29 + 7) & 0xFF)

    let original = data
    expect Crypto.chacha20Xor(key, nonce, data, data, 1)
    Swag.assert(!sameChaChaBytes(data, original))

    // Each block of the result is the matching key-stream block folded into the input, so the
    // counter advances by exactly one block and never repeats one.
    for index in 3
    {
        let block = expect Crypto.chacha20Block(key, cast(u32) (1 + index), nonce)
        let start = index * Crypto.ChaCha20BlockSize
        let count = Math.min(Count - start, Crypto.ChaCha20BlockSize)
        for i in count do
            Swag.assert(data[start + i] == original[start + i] ^ block[i])
    }

    expect Crypto.chacha20Xor(key, nonce, data, data, 1)
    Swag.assert(sameChaChaBytes(data, original))
}

// Four-block batches, their neighboring tails, and exact in-place operation match the public
// single-block definition byte for byte.
#test
{
    let key   = testKey()
    let nonce = testNonce()
    var source:   [1025] u8
    var actual:   [1025] u8
    var expected: [1025] u8
    for source.count do
        source[Swag.index] = cast(u8) ((cast(u64) Swag.index * 47 + 13) & 0xFF)

    let lengths: [15] u64 = [0, 1, 63, 64, 65, 255, 256, 257, 511, 512, 513, 767, 768, 1024, 1025]
    for length in lengths
    {
        for actual.count
        {
            actual[Swag.index]   = 0xA5
            expected[Swag.index] = 0xA5
        }

        scalarChaCha20Xor(key, nonce, Swag.makeSlice(source.buffer, length), Swag.makeSlice(expected.buffer, length), 7)
        expect Crypto.chacha20Xor(key, nonce, Swag.makeSlice(source.buffer, length), Swag.makeSlice(actual.buffer, length), 7)
        Swag.assert(sameChaChaBytes(actual, expected))

        Memory.copy(actual.buffer, source.buffer, source.count)
        expect Crypto.chacha20Xor(key, nonce, Swag.makeSlice(actual.buffer, length), Swag.makeSlice(actual.buffer, length), 7)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, length) == 0)
        for i in length until actual.count do
            Swag.assert(actual[i] == source[i])
    }

    scalarChaCha20Xor(key, nonce, source[until 256], expected[until 256], Swag.U32.Max - 3)
    expect Crypto.chacha20Xor(key, nonce, source[until 256], actual[until 256], Swag.U32.Max - 3)
    Swag.assert(Memory.compare(actual.buffer, expected.buffer, 256) == 0)
}

// The block counter is 32 bits wide. Its last value is usable; asking for one block more than
// the range holds is rejected rather than silently repeating the key stream.
#test
{
    let key   = testKey()
    let nonce = testNonce()

    var lastBlock: [1] u8
    expect Crypto.chacha20Xor(key, nonce, lastBlock, lastBlock, Swag.U32.Max)

    var twoBlocks: [Crypto.ChaCha20BlockSize + 1] u8
    discard catch Crypto.chacha20Xor(key, nonce, twoBlocks, twoBlocks, Swag.U32.Max) as overflowError
    Swag.assert(overflowError is Errors.OverflowError)
}

// A wrong key, nonce, or destination length is a caller mistake, reported before anything is
// written.
#test
{
    let key   = testKey()
    let nonce = testNonce()

    var out: [16] u8
    discard catch Crypto.chacha20Block(key[until 31], 0, nonce) as keyError
    Swag.assert(keyError is Errors.BadParameterError)
    discard catch Crypto.chacha20Block(key, 0, nonce[until 11]) as nonceError
    Swag.assert(nonceError is Errors.BadParameterError)

    var shorter: [8] u8
    discard catch Crypto.chacha20Xor(key, nonce, out, shorter) as sizeError
    Swag.assert(sizeError is Errors.BadParameterError)

    // An empty message is not an error and touches nothing.
    var untouched: [1] u8 = [0x42]
    expect Crypto.chacha20Xor(key, nonce, untouched[until 0], untouched[until 0])
    Swag.assert(untouched[0] == 0x42)
}

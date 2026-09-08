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
    for index in source.count do
        source[index] = cast(u8) ((cast(u64) index * 47 + 13) & 0xFF)

    let lengths: [15] u64 = [0, 1, 63, 64, 65, 255, 256, 257, 511, 512, 513, 767, 768, 1024, 1025]
    for length in lengths
    {
        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
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

// Native partitions match the single-block definition, including unaligned buffers, tails,
// exact in-place XOR and the final legal counter. Sentinels protect both ends of every view.
#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    let key   = testKey()
    let nonce = testNonce()
    const Capacity = 2 * 65536 + 258
    var source:   Array'u8
    var actual:   Array'u8
    var expected: Array'u8
    source.resize(Capacity)
    actual.resize(Capacity)
    expected.resize(Capacity)
    for index in source.count do
        source[index] = cast(u8) ((index * 47 + 13) & 0xFF)

    let lengths: [8] u64 = [65535, 65536, 65537, 65599, 65600, 65791, 65792, Capacity - 2]
    for length in lengths
    {
        Memory.set(actual.buffer!, 0xA5, actual.count)
        Memory.set(expected.buffer!, 0xA5, expected.count)
        let input     = source.toSlice()[1 until length + 1]
        let output    = actual.toSlice()[1 until length + 1]
        let reference = expected.toSlice()[1 until length + 1]
        let blocks    = (length + Crypto.ChaCha20BlockSize - 1) / Crypto.ChaCha20BlockSize
        let first     = Swag.U32.Max - cast(u32) (blocks - 1)
        scalarChaCha20Xor(key, nonce, input, reference, first)
        expect Crypto.chacha20Xor(key, nonce, input, output, first)
        Swag.assert(sameChaChaBytes(actual.toSlice(), expected.toSlice()))

        Memory.copy(actual.buffer!, source.buffer!, source.count)
        expect Crypto.chacha20Xor(key, nonce, output, output, first)
        Swag.assert(sameChaChaBytes(output, reference))
        Swag.assert(actual[0] == source[0])
        for index in length + 1 until actual.count do
            Swag.assert(actual[index] == source[index])
    }

    // Reject the whole request before submitting work when the last block would wrap.
    Memory.set(actual.buffer!, 0xA5, actual.count)
    let tooLong = actual.toSlice()[until 65537]
    discard catch Crypto.chacha20Xor(key, nonce, source.toSlice()[until 65537], tooLong, Swag.U32.Max - 1023) as overflowError
    Swag.assert(overflowError is Errors.OverflowError)
    for index in actual.count do
        Swag.assert(actual[index] == 0xA5)

    // A caller may already be distributing records through the same pool. Nested joins
    // must complete, and each invocation keeps its own destination and stream scratch.
    let input     = source.toSlice()[1 until Capacity - 1]
    let reference = expected.toSlice()[1 until Capacity - 1]
    let first     = Swag.U32.Max - cast(u32) ((input.count - 1) / Crypto.ChaCha20BlockSize)
    let keyPtr    = &key
    let noncePtr  = &nonce
    parallel for |keyPtr, noncePtr, input, reference, first| record in 3
    {
        var encrypted: Array'u8
        encrypted.resize(input.count)
        expect Crypto.chacha20Xor(keyPtr[], noncePtr[], input, encrypted.toSlice(), first)
        Swag.assert(sameChaChaBytes(encrypted.toSlice(), reference))
    }
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

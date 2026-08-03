#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

func cryptoBytesEqual(left, right: const [..] u8)->bool
{
    return @countof(left) == @countof(right) and
           @memcmp(@dataof(left), @dataof(right), @countof(left)) == 0
}

#test
{
    let key      = @mkslice(cast(const [*] u8) @dataof("key"), 3)
    let text     = "The quick brown fox jumps over the lazy dog"
    let expected: [32] u8 = [
        0xF7, 0xBC, 0x83, 0xF4, 0x30, 0x53, 0x84, 0x24,
        0xB1, 0x32, 0x98, 0xE6, 0xAA, 0x6F, 0xB1, 0x43,
        0xEF, 0x4D, 0x59, 0xA1, 0x49, 0x46, 0x17, 0x59,
        0x97, 0x47, 0x9D, 0xBC, 0x2D, 0x1A, 0x3C, 0xD8]

    let actual = Crypto.HmacSha256.compute(key,
        @mkslice(cast(const [*] u8) @dataof(text), @countof(text)))
    @assert(cryptoBytesEqual(actual, expected))

    var incremental = Crypto.HmacSha256.create(key)
    incremental.update(@mkslice(cast(const [*] u8) @dataof(text), 12))
    incremental.update(@mkslice(cast(const [*] u8) @dataof(text) + 12, @countof(text) - 12))
    let split = incremental.finalize()
    @assert(cryptoBytesEqual(split, expected))
    @assert(!incremental.initialized)
}

#test
{
    let password = @mkslice(cast(const [*] u8) @dataof("password"), 8)
    let salt     = @mkslice(cast(const [*] u8) @dataof("salt"), 4)
    let expected: [64] u8 = [
        0xAE, 0x4D, 0x0C, 0x95, 0xAF, 0x6B, 0x46, 0xD3,
        0x2D, 0x0A, 0xDF, 0xF9, 0x28, 0xF0, 0x6D, 0xD0,
        0x2A, 0x30, 0x3F, 0x8E, 0xF3, 0xC2, 0x51, 0xDF,
        0xD6, 0xE2, 0xD8, 0x5A, 0x95, 0x47, 0x4C, 0x43,
        0x83, 0x06, 0x51, 0xAF, 0xCB, 0x5C, 0x86, 0x2F,
        0x0B, 0x24, 0x9B, 0xD0, 0x31, 0xF7, 0xA6, 0x75,
        0x20, 0xD1, 0x36, 0x47, 0x0F, 0x5E, 0xC2, 0x71,
        0xEC, 0xE9, 0x1C, 0x07, 0x77, 0x32, 0x53, 0xD9]

    var actual: [64] u8
    expect Crypto.pbkdf2HmacSha256(password, salt, 2, actual)
    @assert(cryptoBytesEqual(actual, expected))

    var partial: [40] u8
    expect Crypto.pbkdf2HmacSha256(password, salt, 2, partial)
    @assert(cryptoBytesEqual(partial, expected[until 40]))

    discard catch Crypto.pbkdf2HmacSha256(password, salt, 0, partial) as err
    @assert(err is Errors.BadParameterError)
}

#test
{
    var key: [Crypto.ChaCha20KeySize] u8
    for [i] in Crypto.ChaCha20KeySize do
        key[i] = cast(u8) i
    let nonce: [Crypto.ChaCha20NonceSize] u8 = [
        0x00, 0x00, 0x00, 0x09, 0x00, 0x00,
        0x00, 0x4A, 0x00, 0x00, 0x00, 0x00]
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
    @assert(cryptoBytesEqual(block, expected))

    var data: [137] u8
    for value, [i] in data do
        data[i] = cast(u8) ((i * 29 + 7) & 0xFF)
    let original = data
    expect Crypto.chacha20Xor(key, nonce, data, data, 1)
    @assert(!cryptoBytesEqual(data, original))
    expect Crypto.chacha20Xor(key, nonce, data, data, 1)
    @assert(cryptoBytesEqual(data, original))

    var lastCounterByte: [1] u8
    expect Crypto.chacha20Xor(key, nonce, lastCounterByte, lastCounterByte, Swag.U32.Max)
}

#test
{
    let empty = @mkslice(cast(const [*] u8) @dataof(""), 0)
    let one:   [1] u8 = [1]
    let other: [1] u8 = [2]
    @assert(Crypto.constantTimeEqual(empty, empty))
    @assert(Crypto.constantTimeEqual(one, one))
    @assert(!Crypto.constantTimeEqual(one, other))
    @assert(!Crypto.constantTimeEqual(empty, one))

    var random: [64] u8
    expect Crypto.randomBytes(random)
    var anyNonZero: bool
    for byte in random do
        anyNonZero = anyNonZero or byte != 0
    @assert(anyNonZero)

    Crypto.secureClear(random)
    for byte in random do
        @assert(byte == 0)
}

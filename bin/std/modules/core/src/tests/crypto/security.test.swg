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
    let key               = @mkslice(cast(const [*] u8) @dataof("key"), 3)
    let text              = "The quick brown fox jumps over the lazy dog"
    let expected: [32] u8 = [
        0xF7, 0xBC, 0x83, 0xF4, 0x30, 0x53, 0x84, 0x24,
        0xB1, 0x32, 0x98, 0xE6, 0xAA, 0x6F, 0xB1, 0x43,
        0xEF, 0x4D, 0x59, 0xA1, 0x49, 0x46, 0x17, 0x59,
        0x97, 0x47, 0x9D, 0xBC, 0x2D, 0x1A, 0x3C, 0xD8]

    let actual = Crypto.HmacSha256.compute(key, @mkslice(cast(const [*] u8) @dataof(text), @countof(text)))
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
    let password          = @mkslice(cast(const [*] u8) @dataof("password"), 8)
    let salt              = @mkslice(cast(const [*] u8) @dataof("salt"), 4)
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

    var tails: [64] u8
    for length in 65
    {
        for @countof(tails) do
            tails[@index] = 0xA5
        expect Crypto.pbkdf2HmacSha256(password, salt, 2, @mkslice(@dataof(tails), length))
        for i in length do
            @assert(tails[i] == expected[i])
        for i in length until @countof(tails) do
            @assert(tails[i] == 0xA5)
    }

    discard catch Crypto.pbkdf2HmacSha256(password, salt, 0, partial) as err
    @assert(err is Errors.BadParameterError)
}

#test
{
    let empty         = @mkslice(cast(const [*] u8) @dataof(""), 0)
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

#test
{
    var left:  [112] u8
    var right: [112] u8
    for i in 112
    {
        left[i]  = cast(u8) ((i * 29 + 3) & 0xFF)
        right[i] = left[i]
    }

    for offset in 16
    {
        for length in 81
        {
            let a = left[offset until offset + length]
            let b = right[offset until offset + length]
            @assert(Crypto.constantTimeEqual(a, b))
            if length
            {
                right[offset + length - 1] ^= 0x80
                @assert(!Crypto.constantTimeEqual(a, b))
                right[offset + length - 1] ^= 0x80
            }
        }
    }
}

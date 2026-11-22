#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func pbkdf2HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func pbkdf2HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((pbkdf2HexDigit(text[index]) << 4) | pbkdf2HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    let key  = cast(const [..] u8, "key")
    let text = "The quick brown fox jumps over the lazy dog"
    let expected: [32] u8 = [
        0xF7, 0xBC, 0x83, 0xF4, 0x30, 0x53, 0x84, 0x24,
        0xB1, 0x32, 0x98, 0xE6, 0xAA, 0x6F, 0xB1, 0x43,
        0xEF, 0x4D, 0x59, 0xA1, 0x49, 0x46, 0x17, 0x59,
        0x97, 0x47, 0x9D, 0xBC, 0x2D, 0x1A, 0x3C, 0xD8]

    let actual = Crypto.HmacSha256.compute(key, cast(const [..] u8, text))
    Swag.require(Slice.equals(actual, expected))

    var incremental = Crypto.HmacSha256.create(key)
    incremental.update(cast(const [..] u8, text[until 12]))
    incremental.update(cast(const [..] u8, text[12 to]))
    let split = incremental.finalize()
    Swag.require(Slice.equals(split, expected))
    Swag.require(not incremental.initialized)
}

#test
{
    var key: [131] u8
    Memory.set(key.buffer, 0xAA'u8, key.count)
    let data = cast(const [..] u8, "Test Using Larger Than Block-Size Key - Hash Key First")
    const expected: [32] u8 = [
        0x60, 0xE4, 0x31, 0x59, 0x1E, 0xE0, 0xB6, 0x7F,
        0x0D, 0x8A, 0x26, 0xAA, 0xCB, 0xF5, 0xB7, 0x7F,
        0x8E, 0x0B, 0xC6, 0x21, 0x37, 0x28, 0xC5, 0x14,
        0x05, 0x46, 0x04, 0x0F, 0x0E, 0xE3, 0x7F, 0x54]

    Swag.require(Slice.equals(Crypto.HmacSha256.compute(key, data), expected))
}

#test
{
    let password = cast(const [..] u8, "password")
    let salt     = cast(const [..] u8, "salt")
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
    Swag.require(Slice.equals(actual, expected))

    var overlapping: [64] u8
    Memory.copy(overlapping.buffer, password.buffer, password.count)
    let overlappingPassword = cast(const [..] u8, overlapping[until 8])
    expect Crypto.pbkdf2HmacSha256(overlappingPassword, salt, 2, overlapping)
    Swag.require(Slice.equals(overlapping, expected))

    var emptyOutput: [1] u8
    expect Crypto.pbkdf2HmacSha256(password, salt, 1, emptyOutput[until 0])

    var partial: [40] u8
    expect Crypto.pbkdf2HmacSha256(password, salt, 2, partial)
    Swag.require(Slice.equals(partial, expected[until 40]))

    var tails: [64] u8
    for length in 65
    {
        for index in tails.count do
            tails[index] = 0xA5
        expect Crypto.pbkdf2HmacSha256(password, salt, 2, tails[until length])
        Swag.require(Slice.equals(tails[until length], expected[until length]))
        for i in length until tails.count do
            Swag.require(tails[i] == 0xA5)
    }

    var errOutcome: Swag.Error
    discard catch Crypto.pbkdf2HmacSha256(password, salt, 0, partial) as errOutcome
    let err = errOutcome.value()
    Swag.require((err is Errors.BadParameterError))
}

#test
{
    let empty         = cast(const [..] u8, "")
    let one:   [1] u8 = [1]
    let other: [1] u8 = [2]
    Swag.require(Crypto.constantTimeEqual(empty, empty))
    Swag.require(Crypto.constantTimeEqual(one, one))
    Swag.require(not Crypto.constantTimeEqual(one, other))
    Swag.require(not Crypto.constantTimeEqual(empty, one))

    var vectorBytes: [64] u8
    var sameBytes:   [64] u8
    Swag.require(Crypto.constantTimeEqual(vectorBytes, sameBytes))
    sameBytes[0] = 1
    Swag.require(not Crypto.constantTimeEqual(vectorBytes, sameBytes))
    sameBytes[0]  = 0
    sameBytes[63] = 1
    Swag.require(not Crypto.constantTimeEqual(vectorBytes, sameBytes))

    var random: [64] u8
    expect Crypto.randomBytes(random)
    var anyNonZero: bool
    for byte in random do
        anyNonZero = anyNonZero or byte != 0
    Swag.require(anyNonZero)

    Crypto.secureClear(random)
    for byte in random do
        Swag.require(byte == 0)
}

#test
{
    let password    = cast(const [..] u8, "password")
    let salt        = cast(const [..] u8, "salt")
    let expected224 = pbkdf2HexBytes("93200ffa96c5776d38fa10abdf8f5bfc0054b9718513df472d2331d2d1e66a3f97b510224f700ce72581ffb10a1c99ec99a8cc1b951851a71f30d9265fccf912")
    let expected384 = pbkdf2HexBytes("54f775c6d790f21930459162fc535dbf04a939185127016a04176a0730c6f1f4fb48832ad1261baadd2cedd50814b1c806ad1bbf43ebdc9d047904bf7ceafe1e")
    let expected512 = pbkdf2HexBytes("e1d9c16aa681708a45f5c7c4e215ceb66e011a2e9f0040713f18aefdb866d53cf76cab2868a39b9f7840edce4fef5a82be67335c77a6068e04112754f27ccf4e")

    var output224: [64] u8
    var output384: [64] u8
    var output512: [64] u8
    expect Crypto.pbkdf2HmacSha224(password, salt, 2, output224)
    expect Crypto.pbkdf2HmacSha384(password, salt, 2, output384)
    expect Crypto.pbkdf2HmacSha512(password, salt, 2, output512)
    Swag.require(Crypto.constantTimeEqual(output224, expected224.toSlice()))
    Swag.require(Crypto.constantTimeEqual(output384, expected384.toSlice()))
    Swag.require(Crypto.constantTimeEqual(output512, expected512.toSlice()))

    var overlapping: [64] u8
    Swag.memcpy(&overlapping[0], password.buffer, password.count)
    expect Crypto.pbkdf2HmacSha224(cast(const [..] u8, overlapping[until 8]), salt, 2, overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected224.toSlice()))

    var empty: [1] u8
    expect Crypto.pbkdf2HmacSha512(password, salt, 1, empty[until 0])
}

#test
{
    var left:  [112] u8
    var right: [112] u8
    for i in 112
    {
        left[i]  = cast(u8, ((i * 29 + 3) & 0xFF))
        right[i] = left[i]
    }

    for offset in 16
    {
        for length in 81
        {
            let a = left[offset until offset + length]
            let b = right[offset until offset + length]
            Swag.require(Crypto.constantTimeEqual(a, b))
            if length
            {
                right[offset + length - 1] ^= 0x80
                Swag.require(not Crypto.constantTimeEqual(a, b))
                right[offset + length - 1] ^= 0x80
            }
        }
    }
}

// The host fills requests larger than its single-call entropy limit without touching neighbors.
#test
{
    var bytes: [1026] u8
    for length in [0'u64, 1, 255, 256, 257, 1024]
    {
        bytes[0] = 19
        bytes[length + 1] = 73
        let range = bytes[1 until length + 1]
        expect Crypto.randomBytes(range)
        Crypto.secureClear(range)
        for value in range do
            Swag.require(value == 0)
        Swag.require(bytes[0] == 19 and bytes[length + 1] == 73)
    }
}

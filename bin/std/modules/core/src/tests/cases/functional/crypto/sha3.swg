#global if #command == Swag.CompilerCommand.Test
#global private

func sha3HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func sha3HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((sha3HexDigit(text[index]) << 4) | sha3HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

func assertSha3(data: const [..] u8, expected: string)
{
    let reference = sha3HexBytes(expected)
    var oneShot: Array'u8
    oneShot.resize(reference.count)
    expect Hash.Sha3.compute(data, oneShot.toSlice())
    Swag.require(Crypto.constantTimeEqual(oneShot.toSlice(), reference.toSlice()))

    var streamed: Array'u8
    streamed.resize(reference.count)
    var hash   = expect Hash.Sha3.create(reference.count)
    var offset = 0'u64
    while offset < data.count
    {
        let count = Math.min(data.count - offset, 13'u64)
        hash.update(data[offset until offset + count])
        offset += count
    }

    expect hash.finalize(streamed.toSlice())
    Swag.require(Crypto.constantTimeEqual(streamed.toSlice(), reference.toSlice()))
}

func assertShake(data: const [..] u8, securityBits: u64, expected: string)
{
    let reference = sha3HexBytes(expected)
    var oneShot: Array'u8
    oneShot.resize(reference.count)
    expect Hash.Shake.compute(data, securityBits, oneShot.toSlice())
    Swag.require(Crypto.constantTimeEqual(oneShot.toSlice(), reference.toSlice()))

    var streamed: Array'u8
    streamed.resize(reference.count)
    var shake  = expect Hash.Shake.create(securityBits)
    var offset = 0'u64
    while offset < data.count
    {
        let count = Math.min(data.count - offset, 17'u64)
        shake.update(data[offset until offset + count])
        offset += count
    }

    expect shake.finalize(streamed.toSlice())
    Swag.require(Crypto.constantTimeEqual(streamed.toSlice(), reference.toSlice()))
}

#test
{
    assertSha3("", "6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7")
    assertSha3("", "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
    assertSha3("", "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004")
    assertSha3("", "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26")

    assertShake("", 128, "7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26")
    assertShake("", 256, "46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be")
}

#test
{
    var input: [400] u8
    for index in input.count do
        input[index] = cast(u8, ((index * 37 + 11) & 0xFF))

    for digestSize in [28'u64, 32, 48, 64]
    {
        var expected: Array'u8
        expected.resize(digestSize)
        expect Hash.Sha3.compute(input, expected.toSlice())

        var actual: Array'u8
        actual.resize(digestSize)
        var hash = expect Hash.Sha3.create(digestSize)
        hash.update(input[until 1])
        hash.update(input[1 until 143])
        hash.update(input[143 until 288])
        hash.update(input[288 to])
        expect hash.finalize(actual.toSlice())
        Swag.require(Crypto.constantTimeEqual(actual.toSlice(), expected.toSlice()))
    }

    var short:   [31] u8
    var hash = expect Hash.Sha3.create(32)
    var outcome: Swag.Error
    discard catch hash.finalize(short) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
}

#test
{
    var input: [400] u8
    for index in input.count do
        input[index] = cast(u8, ((index * 19 + 5) & 0xFF))

    for securityBits in [128'u64, 256]
    {
        var expected: [400] u8
        expect Hash.Shake.compute(input, securityBits, expected)

        var actual: [400] u8
        var shake = expect Hash.Shake.create(securityBits)
        shake.update(input[until 167])
        shake.update(input[167 until 336])
        shake.update(input[336 to])
        expect shake.finalize(actual)
        Swag.require(Crypto.constantTimeEqual(actual, expected))
    }

    var bad: Swag.Error
    discard catch Hash.Shake.create(192) as bad
    Swag.require(bad.value() is Errors.BadParameterError)
}

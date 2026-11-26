#global if #command == Swag.CompilerCommand.Test
#global private

func blake2sHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func blake2sHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((blake2sHexDigit(text[index]) << 4) | blake2sHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

func assertBlake2s(data: const [..] u8, expected: string)
{
    let reference = blake2sHexBytes(expected)
    var oneShot: Array'u8
    oneShot.resize(reference.count)
    expect Hash.Blake2s.compute(data, oneShot.toSlice())
    Swag.require(Crypto.constantTimeEqual(oneShot.toSlice(), reference.toSlice()))

    var streamed: Array'u8
    streamed.resize(reference.count)
    var hash   = expect Hash.Blake2s.create(reference.count)
    var offset = 0'u64
    while offset < data.count
    {
        let count = Math.min(data.count - offset, 7'u64)
        hash.update(data[offset until offset + count])
        offset += count
    }

    expect hash.finalize(streamed.toSlice())
    Swag.require(Crypto.constantTimeEqual(streamed.toSlice(), reference.toSlice()))
}

#test
{
    // RFC 7693's BLAKE2s-256 examples.
    assertBlake2s("", "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9")
    assertBlake2s("abc", "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982")
}

#test
{
    var key:   [32] u8
    var input: [64] u8
    for index in 32 do
        key[index] = cast(u8, index)
    for index in 64 do
        input[index] = cast(u8, index)

    var actual: [32] u8
    expect Hash.Blake2s.computeKeyed(key, input, actual)
    let expected = blake2sHexBytes("8975b0577fd35566d750b362b0897a26c399136df07bababbde6203ff2954ed4")
    Swag.require(Crypto.constantTimeEqual(actual, expected.toSlice()))

    for digestSize in [1'u64, 16, 32]
    {
        var oneShot: Array'u8
        oneShot.resize(digestSize)
        expect Hash.Blake2s.compute(input, oneShot.toSlice())

        var incremental: Array'u8
        incremental.resize(digestSize)
        var hash = expect Hash.Blake2s.create(digestSize)
        hash.update(input[until 63])
        hash.update(input[63 to])
        expect hash.finalize(incremental.toSlice())
        Swag.require(Crypto.constantTimeEqual(oneShot.toSlice(), incremental.toSlice()))
    }
}

#test
{
    // Start at an odd byte, including when the sequence ends exactly on a block boundary.
    var input: [130] u8
    for index in input.count do
        input[index] = cast(u8, index)

    assertBlake2s(input[1 until 64], "98b4ba19442c0e35f30a23dd9821711f4c4599331b36a77ad4bd39dd1ae46002")
    assertBlake2s(input[1 until 65], "aa9932410694932a282715ae15f432f37f0ffac012d20a6019bdb008bb21fac7")
    assertBlake2s(input[1 until 66], "35492839ca7bb72312e2bc6e091e19aaf3c2b63dcd9feb120ae3744291cd292c")
    assertBlake2s(input[1 until 129], "d510becea458ec8fb7795a3fe0ca2b356ae0509940f098e4fbaff7646b035156")
    assertBlake2s(input[1 until 130], "f78a2339ce599c492d0757dc8528b30c6e69e4b5e32cddceb4629c07d2494e19")
}

#test
{
    var oversizedKey: [Hash.Blake2sMaxKeySize + 1] u8
    var digest:       [32] u8
    var keyError:     Swag.Error
    discard catch Hash.Blake2s.computeKeyed(oversizedKey, "abc", digest) as keyError
    Swag.require(keyError.value() is Errors.BadParameterError)

    var digestError: Swag.Error
    discard catch Hash.Blake2s.create(0) as digestError
    Swag.require(digestError.value() is Errors.BadParameterError)

    var hash = expect Hash.Blake2s.create(32)
    var wrongLength: [16] u8
    var outputError: Swag.Error
    discard catch hash.finalize(wrongLength) as outputError
    Swag.require(outputError.value() is Errors.BadParameterError)
}

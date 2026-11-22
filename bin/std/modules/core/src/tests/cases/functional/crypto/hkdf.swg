#global if #command == Swag.CompilerCommand.Test
#global private

func hkdfHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func hkdfHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((hkdfHexDigit(text[index]) << 4) | hkdfHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    var inputKeyMaterial: [22] u8
    Memory.set(inputKeyMaterial.buffer, 0x0B'u8, inputKeyMaterial.count)
    const Salt = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    const Info = [0xF0'u8, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9]
    let expected = hkdfHexBytes("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")

    var output: [42] u8
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, Info, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    // Expansion must keep reading the original info when the output covers it.
    var overlapping: [42] u8
    for index in 10 do
        overlapping[index] = Info[index]
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, overlapping[until 10], overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected.toSlice()))

    // Exercise the multi-block expansion with several splits at digest boundaries.
    var longer: [96] u8
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, Info, longer)
    var split: [96] u8
    var incrementalInput: [10] u8
    for index in 10 do
        incrementalInput[index] = Info[index]
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, incrementalInput, split)
    Swag.require(Crypto.constantTimeEqual(longer, split))

    var emptyStorage: [1] u8
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, Info, emptyStorage[until 0])

    var maximum: [Crypto.HkdfSha256MaxOutputSize] u8
    expect Crypto.hkdfSha256(Salt, inputKeyMaterial, Info, maximum)
}

#test
{
    var inputKeyMaterial: [22] u8
    Memory.set(inputKeyMaterial.buffer, 0x0B'u8, inputKeyMaterial.count)
    const Salt = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    const Info = [0xF0'u8, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9]
    let expected = hkdfHexBytes("832390086cda71fb47625bb5ceb168e4c8e26a1a16ed34d9fc7fe92c1481579338da362cb8d9f925d7cb")

    var output: [42] u8
    expect Crypto.hkdfSha512(Salt, inputKeyMaterial, Info, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    // The output covers `info`; expansion must read the original info throughout.
    var overlapping: [42] u8
    for index in 10 do
        overlapping[index] = Info[index]
    expect Crypto.hkdfSha512(Salt, inputKeyMaterial, overlapping[until 10], overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected.toSlice()))

    var tooLong: [Crypto.HkdfSha512MaxOutputSize + 1] u8
    var error:   Swag.Error
    discard catch Crypto.hkdfSha512(Salt, inputKeyMaterial, Info, tooLong) as error
    Swag.require(error.value() is Errors.BadParameterError)

    var maximum: [Crypto.HkdfSha512MaxOutputSize] u8
    expect Crypto.hkdfSha512(Salt, inputKeyMaterial, Info, maximum)
}

#test
{
    var inputKeyMaterial: [22] u8
    Memory.set(inputKeyMaterial.buffer, 0x0B'u8, inputKeyMaterial.count)
    const Salt = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    const Info = [0xF0'u8, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9]
    let expected = hkdfHexBytes("2f21cd7cbc818ca5c561b933728e2e08e154a87e1432399a820dee13aa222d0cee6152fa539ab70f8e80")

    var output: [42] u8
    expect Crypto.hkdfSha224(Salt, inputKeyMaterial, Info, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    var overlapping: [42] u8
    for index in 10 do
        overlapping[index] = Info[index]
    expect Crypto.hkdfSha224(Salt, inputKeyMaterial, overlapping[until 10], overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected.toSlice()))

    var tooLong: [Crypto.HkdfSha224MaxOutputSize + 1] u8
    var error:   Swag.Error
    discard catch Crypto.hkdfSha224(Salt, inputKeyMaterial, Info, tooLong) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    var inputKeyMaterial: [22] u8
    Memory.set(inputKeyMaterial.buffer, 0x0B'u8, inputKeyMaterial.count)
    const Salt = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    const Info = [0xF0'u8, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9]
    let expected = hkdfHexBytes("9b5097a86038b805309076a44b3a9f38063e25b516dcbf369f394cfab43685f748b6457763e4f0204fc5")

    var output: [42] u8
    expect Crypto.hkdfSha384(Salt, inputKeyMaterial, Info, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    var overlapping: [42] u8
    for index in 10 do
        overlapping[index] = Info[index]
    expect Crypto.hkdfSha384(Salt, inputKeyMaterial, overlapping[until 10], overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected.toSlice()))

    var tooLong: [Crypto.HkdfSha384MaxOutputSize + 1] u8
    var error:   Swag.Error
    discard catch Crypto.hkdfSha384(Salt, inputKeyMaterial, Info, tooLong) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

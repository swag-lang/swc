#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func scryptHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func scryptHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((scryptHexDigit(text[index]) << 4) | scryptHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    let expected = scryptHexBytes("77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
    var output: [64] u8
    expect Crypto.scrypt("", "", 16, 1, 1, 8192, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))
}

#test
{
    let password = cast(const [..] u8, "password")
    let salt     = cast(const [..] u8, "NaCl")
    let expected = scryptHexBytes("c247eabb7c5d3894e045edf2a4e992737d953a3b181f2e482c2b7c3a7060a11ca0d5e45a98745bfba7fa549c0db559591b81747c9b37e842ebac53ebdcfdee6d")
    Swag.setWorkerCount(4)
    var output: [64] u8
    expect Crypto.scrypt(password, salt, 16, 1, 2, 8192, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    var overlapping: [64] u8
    Swag.memcpy(&overlapping[0], password.buffer, password.count)
    expect Crypto.scrypt(cast(const [..] u8, overlapping[until 8]), salt, 16, 1, 2, 8192, overlapping)
    Swag.require(Crypto.constantTimeEqual(overlapping, expected.toSlice()))
}

#test
{
    var output: [32] u8
    var error:  Swag.Error
    discard catch Crypto.scrypt("password", "salt", 3, 1, 1, 8192, output) as error
    Swag.require(error.value() is Errors.BadParameterError)
    discard catch Crypto.scrypt("password", "salt", 16, 1, 1, 1024, output) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

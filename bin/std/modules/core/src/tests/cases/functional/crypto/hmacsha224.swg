#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func hmacSha224HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func hmacSha224HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((hmacSha224HexDigit(text[index]) << 4) | hmacSha224HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    var key: [20] u8
    for index in key.count do
        key[index] = 0x0B
    let data     = cast(const [..] u8, "Hi There")
    let expected = hmacSha224HexBytes("896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22")
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha224.compute(key, data), expected.toSlice()))

    var incremental = Crypto.HmacSha224.create(key)
    incremental.update(data[until 3])
    incremental.update(data[3 to])
    Swag.require(Crypto.constantTimeEqual(incremental.finalize(), expected.toSlice()))
    Swag.require(not incremental.initialized)
}

#test
{
    let key      = cast(const [..] u8, "Jefe")
    let data     = cast(const [..] u8, "what do ya want for nothing?")
    let expected = hmacSha224HexBytes("a30e01098bc6dbbf45690f3a7e9e6d0f8bbea2a39e6148008fd05e44")
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha224.compute(key, data), expected.toSlice()))
}

#test
{
    var key: [131] u8
    Memory.set(key.buffer, 0xAA'u8, key.count)
    let data     = cast(const [..] u8, "Test Using Larger Than Block-Size Key - Hash Key First")
    let expected = hmacSha224HexBytes("95e9a0db962095adaebe9b2d6f0dbce2d499f112f2d2b7273fa6870e")
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha224.compute(key, data), expected.toSlice()))
}

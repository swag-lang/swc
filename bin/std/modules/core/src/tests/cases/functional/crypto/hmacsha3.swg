#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func hmacSha3HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func hmacSha3HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (hmacSha3HexDigit(text[index]) << 4) | hmacSha3HexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // Standard HMAC-SHA-3 vectors cover SHA3-224, -256, -384, and -512 output sizes.
    var key: [20] u8
    Memory.set(key.buffer, 0x0B'u8, key.count)
    let message     = "Hi There"
    let expected224 = hmacSha3HexBytes("3b16546bbc7be2706a031dcafd56373d9884367641d8c59af3c860f7")
    let expected256 = hmacSha3HexBytes("ba85192310dffa96e2a3a40e69774351140bb7185e1202cdcc917589f95e16bb")
    let expected384 = hmacSha3HexBytes("68d2dcf7fd4ddd0a2240c8a437305f61fb7334cfb5d0226e1bc27dc10a2e723a20d370b47743130e26ac7e3d532886bd")
    let expected512 = hmacSha3HexBytes("eb3fbd4b2eaab8f5c504bd3a41465aacec15770a7cabac531e482f860b5ec7ba47ccb2c6f2afce8f88d22b6dc61380f23a668fd3888bb80537c0a0b86407689e")
    var digest224: [28] u8
    var digest256: [32] u8
    var digest384: [48] u8
    var digest512: [64] u8
    expect Crypto.HmacSha3.compute(key, message, 28, digest224)
    expect Crypto.HmacSha3.compute(key, message, 32, digest256)
    expect Crypto.HmacSha3.compute(key, message, 48, digest384)
    expect Crypto.HmacSha3.compute(key, message, 64, digest512)
    Swag.require(Crypto.constantTimeEqual(digest224, expected224.toSlice()))
    Swag.require(Crypto.constantTimeEqual(digest256, expected256.toSlice()))
    Swag.require(Crypto.constantTimeEqual(digest384, expected384.toSlice()))
    Swag.require(Crypto.constantTimeEqual(digest512, expected512.toSlice()))
}

#test
{
    // A key longer than the SHA3-256 rate is hashed first; updates may split at any byte.
    var key: Array'u8
    key.resize(200)
    for index in key.count do
        key[index] = cast(u8, index)
    var message: Array'u8
    message.resize(87)
    for index in message.count do
        message[index] = cast(u8, index)
    let expected = hmacSha3HexBytes("812c453b4f70cbb835bb810f7910c17f16b0e3ebd2c71beceff07a4f9d564759")
    var actual: [32] u8
    expect Crypto.HmacSha3.compute(key.toSlice(), message.toSlice(), 32, actual)
    Swag.require(Crypto.constantTimeEqual(actual, expected.toSlice()))

    var hmac = expect Crypto.HmacSha3.create(key.toSlice(), 32)
    hmac.update(message[until 19])
    hmac.update(message[19 until 73])
    hmac.update(message[73 until])
    var incremental: [32] u8
    expect hmac.finalize(incremental)
    Swag.require(Crypto.constantTimeEqual(incremental, expected.toSlice()))
}

#test
{
    var key:           [16] u8
    var message:       [1] u8
    var invalidDigest: [31] u8
    var error:         Swag.Error
    discard catch Crypto.HmacSha3.compute(key, message, 31, invalidDigest) as error
    Swag.require(error.value() is Errors.BadParameterError)

    var wrongOutput: [31] u8
    discard catch Crypto.HmacSha3.compute(key, message, 32, wrongOutput) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    const Rate       = 136
    const KeyLengths = [0'u64, Rate, Rate + 1]
    const Expected   = [
        "ae03f6fe5c1a1d57e25f4d5d4649e37798f2f9234481c7c5717e0fa5e841bb66",
        "d540a91ee13eeca22c254095f45e5c53308dc752587cb08c84939f2c2db7001e",
        "c509196941f8d688a6afddbc953e1e3cc4a6d2ed8321184942e7964933b88429"]

    var keys: [Rate + 2] u8
    for index in keys.count do
        keys[index] = cast(u8, (index * 19 + 3) & 0xFF)
    var message: [152] u8
    for index in message.count do
        message[index] = cast(u8, (index * 37 + 11) & 0xFF)

    var mac = expect Crypto.HmacSha3.create("previous key", 64)
    for length, index in KeyLengths
    {
        mac.update("discarded input")
        expect mac.reset(keys[1 until length + 1], 32)
        mac.update(message[1 until 48])
        mac.update(message[48 to])
        var digest: [32] u8
        expect mac.finalize(digest)
        let expected = hmacSha3HexBytes(Expected[index])
        Swag.require(Crypto.constantTimeEqual(digest, expected.toSlice()))
        expect mac.reset("previous key", 64)
    }
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func kmacHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func kmacHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (kmacHexDigit(text[index]) << 4) | kmacHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // KMAC128 reference vectors cover absent and explicit customization strings.
    let key                = kmacHexBytes("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")
    let message            = kmacHexBytes("00010203")
    let customization      = "KMAC"
    let expected           = kmacHexBytes("e5780b0d3ea6f7d3a429c5706aa43a00fadbd7d49628839e3187243f456ee14e")
    let expectedCustomized = kmacHexBytes("959e24a981ab77f6f4960cba82d0bd3c4799108d14f892838b70a6620856b042")
    var output: [32] u8
    expect Crypto.kmac128(key.toSlice(), message.toSlice(), "", output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))
    expect Crypto.kmac128(key.toSlice(), message.toSlice(), customization, output)
    Swag.require(Crypto.constantTimeEqual(output, expectedCustomized.toSlice()))
}

#test
{
    // KMAC256 and both XOF variants match OpenSSL's SP 800-185 implementation.
    let key            = kmacHexBytes("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")
    let message        = kmacHexBytes("00010203")
    let customization  = "KMAC"
    let expected256    = kmacHexBytes("23513f4f25f6cf7d4e00663ab26223d0a9300a7a3b999220dc77af7d9986d26eb47242c703805abe83ec1fdc64cd992fb0a28fcc5f6f584dd7a051c62e14fff6")
    let expectedXof128 = kmacHexBytes("cd83740bbd92ccc8cf032b1481a0f4460e7ca9dd12b08a0c4031178bacd6ec35")
    let expectedXof256 = kmacHexBytes("1c7f9bf1c335c97dfa48fba50027059230f1ba42ae749ad5342f965dd4d73d0cde89b50b264e199cc6929edfd012b7a13ad7b8fd8f7ddd3f2758068fe2a347f0")
    var output256:    [64] u8
    var outputXof128: [32] u8
    var outputXof256: [64] u8
    expect Crypto.kmac256(key.toSlice(), message.toSlice(), customization, output256)
    expect Crypto.kmacXof128(key.toSlice(), message.toSlice(), "", outputXof128)
    expect Crypto.kmacXof256(key.toSlice(), message.toSlice(), "", outputXof256)
    Swag.require(Crypto.constantTimeEqual(output256, expected256.toSlice()))
    Swag.require(Crypto.constantTimeEqual(outputXof128, expectedXof128.toSlice()))
    Swag.require(Crypto.constantTimeEqual(outputXof256, expectedXof256.toSlice()))
}

#test
{
    var key:    [1] u8
    var empty:  Array'u8
    var output: [1] u8
    var error:  Swag.Error
    discard catch Crypto.kmac128(empty.toSlice(), "", "", output) as error
    Swag.require(error.value() is Errors.BadParameterError)
    discard catch Crypto.kmac256(key, "", "", empty.toSlice()) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    // KMACXOF128 streams long inputs and squeezes beyond one rate block.
    let key      = kmacHexBytes("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")
    let expected = kmacHexBytes("73755e50086f4cd4e981caf3751ad5c516bd2661562925eac57f1121c1b53d8dbcb4e08f3de13cb99f0013e16a657505f9cbb7c8ef958fb4f5fa2058875d7951142344bb26443ec6dec1b96619420c93a119031046a479bd956e1d69d7e62a2866498bc13f85cf2a8877de109a04a160d8d8adbe3ba1ef5bb281e38470f1113136b18ed167879b0fa86c5a51df51dba6876f64baa543dec763fefe9bbbd3a334b124bef606c1c7b0770bece69eb7e662b00ef314d4e621c68565628ad5cb9d3ac60485ee6efa2c10")
    var message: Array'u8
    message.resize(200)
    for index in message.count do
        message[index] = cast(u8, index)
    var output: [200] u8
    expect Crypto.kmacXof128(key.toSlice(), message.toSlice(), "", output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))
}

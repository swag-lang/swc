#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesKeyWrapHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesKeyWrapHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesKeyWrapHexDigit(text[index]) << 4) | aesKeyWrapHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // RFC 3394 section 4 vectors cover 128, 192, and 256-bit wrapping keys.
    let keyData     = aesKeyWrapHexBytes("00112233445566778899aabbccddeeff")
    let key128      = aesKeyWrapHexBytes("000102030405060708090a0b0c0d0e0f")
    let key192      = aesKeyWrapHexBytes("000102030405060708090a0b0c0d0e0f1011121314151617")
    let key256      = aesKeyWrapHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let expected128 = aesKeyWrapHexBytes("1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5")
    let expected192 = aesKeyWrapHexBytes("96778b25ae6ca435f92b5b97c050aed2468ab8a17ad84e5d")
    let expected256 = aesKeyWrapHexBytes("64e8c3f9ce0f5ba263e9777905818a2a93c8191e7d6e8ae7")
    var wrapped128: [24] u8
    var wrapped192: [24] u8
    var wrapped256: [24] u8
    expect Crypto.aesKeyWrap(key128.toSlice(), keyData.toSlice(), wrapped128)
    expect Crypto.aesKeyWrap(key192.toSlice(), keyData.toSlice(), wrapped192)
    expect Crypto.aesKeyWrap(key256.toSlice(), keyData.toSlice(), wrapped256)
    Swag.require(Crypto.constantTimeEqual(wrapped128, expected128.toSlice()))
    Swag.require(Crypto.constantTimeEqual(wrapped192, expected192.toSlice()))
    Swag.require(Crypto.constantTimeEqual(wrapped256, expected256.toSlice()))
    var unwrapped: [16] u8
    expect Crypto.aesKeyUnwrap(key256.toSlice(), wrapped256, unwrapped)
    Swag.require(Crypto.constantTimeEqual(unwrapped, keyData.toSlice()))
}

#test
{
    // RFC 5649 exercises both the single-block special case and multi-block ciphertext stealing.
    let key           = aesKeyWrapHexBytes("5840df6e29b02af1ab493b705bf16ea1")
    let shortKeyData  = aesKeyWrapHexBytes("466f7250617369")
    let shortExpected = aesKeyWrapHexBytes("21f7571c6531cc238baba66be3f0662f")
    let longKeyData   = aesKeyWrapHexBytes("c37b7e6492584340bed12207808941155068f738")
    let longExpected  = aesKeyWrapHexBytes("ed9f0ecfbb761b7365838733e3f42f81a049f077e901f63bfe0519e8a12e9bcf")
    var shortWrapped: [16] u8
    var longWrapped:  [32] u8
    expect Crypto.aesKeyWrapWithPadding(key.toSlice(), shortKeyData.toSlice(), shortWrapped)
    expect Crypto.aesKeyWrapWithPadding(key.toSlice(), longKeyData.toSlice(), longWrapped)
    Swag.require(Crypto.constantTimeEqual(shortWrapped, shortExpected.toSlice()))
    Swag.require(Crypto.constantTimeEqual(longWrapped, longExpected.toSlice()))
    var output: [24] u8
    let outputLength = expect Crypto.aesKeyUnwrapWithPadding(key.toSlice(), longWrapped, output)
    Swag.require(outputLength == longKeyData.count)
    Swag.require(Crypto.constantTimeEqual(output[until outputLength], longKeyData.toSlice()))
}

#test
{
    // Authenticated unwraps leave caller output untouched when an integrity check fails.
    let key = aesKeyWrapHexBytes("000102030405060708090a0b0c0d0e0f")
    var wrapped: [24] u8
    Memory.set(wrapped.buffer, 0'u8, wrapped.count)
    var output: [16] u8
    Memory.set(output.buffer, 0xA5'u8, output.count)
    var error: Swag.Error
    discard catch Crypto.aesKeyUnwrap(key.toSlice(), wrapped, output) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in output do
        Swag.require(byte == 0xA5)

    var paddedWrapped: [16] u8
    Memory.set(paddedWrapped.buffer, 0'u8, paddedWrapped.count)
    var paddedOutput: [8] u8
    Memory.set(paddedOutput.buffer, 0x5A'u8, paddedOutput.count)
    discard catch Crypto.aesKeyUnwrapWithPadding(key.toSlice(), paddedWrapped, paddedOutput) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in paddedOutput do
        Swag.require(byte == 0x5A)
}

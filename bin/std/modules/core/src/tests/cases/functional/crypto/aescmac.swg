#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesCmacHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesCmacHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesCmacHexDigit(text[index]) << 4) | aesCmacHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // NIST SP 800-38B AES-128 vectors cover empty, complete, and partial final blocks.
    let key         = aesCmacHexBytes("2b7e151628aed2a6abf7158809cf4f3c")
    let message     = aesCmacHexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    let expected    = aesCmacHexBytes("51f0bebf7e3b9d92fc49741779363cfe")
    let emptyTag    = aesCmacHexBytes("bb1d6929e95937287fa37d129b756746")
    let blockTag    = aesCmacHexBytes("070a16b46b4d4144f79bdd9dd04a287c")
    let partialTag  = aesCmacHexBytes("dfa66747de9ae63030ca32611497c827")
    var empty: Array'u8
    var emptyOutput = expect Crypto.AesCmac.compute(key.toSlice(), empty.toSlice())
    Swag.require(Crypto.constantTimeEqual(emptyOutput, emptyTag.toSlice()))
    var blockOutput = expect Crypto.AesCmac.compute(key.toSlice(), message[until 16])
    Swag.require(Crypto.constantTimeEqual(blockOutput, blockTag.toSlice()))
    var partialOutput = expect Crypto.AesCmac.compute(key.toSlice(), message[until 40])
    Swag.require(Crypto.constantTimeEqual(partialOutput, partialTag.toSlice()))
    var output = expect Crypto.AesCmac.compute(key.toSlice(), message.toSlice())
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))

    var incremental = expect Crypto.AesCmac.create(key.toSlice())
    expect incremental.update(message[until 13])
    expect incremental.update(message[13 until 37])
    expect incremental.update(message[37 until 52])
    expect incremental.update(message[52 until])
    var incrementalOutput = expect incremental.finalize()
    Swag.require(Crypto.constantTimeEqual(incrementalOutput, expected.toSlice()))
}

#test
{
    // The NIST AES-192 and AES-256 key schedules use the same full-width CMAC output.
    let key192      = aesCmacHexBytes("8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b")
    let key256      = aesCmacHexBytes("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
    let message     = aesCmacHexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    let expected192 = aesCmacHexBytes("a1d5df0eed790f794d77589659f39a11")
    let expected256 = aesCmacHexBytes("e1992190549f6ed5696a2c056c315410")
    var output192   = expect Crypto.AesCmac.compute(key192.toSlice(), message.toSlice())
    var output256   = expect Crypto.AesCmac.compute(key256.toSlice(), message.toSlice())
    Swag.require(Crypto.constantTimeEqual(output192, expected192.toSlice()))
    Swag.require(Crypto.constantTimeEqual(output256, expected256.toSlice()))
}

#test
{
    var invalidKey: [20] u8
    var message:    [16] u8
    var error:      Swag.Error
    discard catch Crypto.AesCmac.compute(invalidKey, message) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

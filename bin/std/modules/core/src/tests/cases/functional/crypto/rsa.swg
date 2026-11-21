#global if #command == Swag.CompilerCommand.Test
#global private

func rsaTestHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func rsaTestHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (rsaTestHexDigit(text[index]) << 4) | rsaTestHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

// Test-only 2048-bit RSA key generated with OpenSSL; never use it outside these fixtures.
func rsaTestModulus()->Array'u8 => rsaTestHexBytes("a1453b93b75c349be851cfc681f572ecbe4a4d884b280099d3a250104bd8fb26c1f749d12c0ee71fa5763e2b304be33cef3497026f7d50162f5a0fe378fa99d627a6dad5ae01346f1845d4f6ca4507864cf4b837b9c19feace8e77273c7789f6e03c1923715672d707c73063cf7a4bf3d2d0595ccc3b4acb32d53c7bc0680330ac61d2634eda13e5ab4381351d17b9c2d6e00808f0af46f549ef9bf20c2dc244c8b61431fb9b6f7a6e3d7270aba6503ed9c98dac093fe250f45eda36fbcdaab2e4928e6565bedf0788578fef1011a43bdcdd583dae509357e9e5fa66f80dbbde7b29cd059733a18fcbe46cf6e91569d8ffa0e3b3626406fa312ce5d6bf9e10e7")

func rsaTestPrivateExponent()->Array'u8 => rsaTestHexBytes("4c6a3f341bae7b9922685d90dc747eabb1f10832dc15cccf16ca32b0be17c6cd931c0724af81323fbb09bfa47c42811e96e3aee82f06cc436ed57870db1ab7791399cad874164b0f970b43c15a8f81e4bfa33784e4265c8d88a955c9482c0639edff5c1400b8ab3abb8b45210e270f452daf9ea04b7f8ecda0bd0c674100a7fd8f09bae86d09dd58feea14688836adbf301c9bb06bbbc4290e82345dc0661bd72cfece9096a4031efd7be6e75b6ce6154790be4deb78e4d9f0503ff23276f8c199caef8e46a7ca4223110addb0de1a0b8ab8a170051b3c01fb53e770978c544fd0b13854a0d21f32df96c33c49961d906f8f2898542c8eb28fc397f1777becbd")

#test
{
    // OpenSSL decodes this fixed OAEP-SHA-256 ciphertext and label with the fixture key.
    let modulus         = rsaTestModulus()
    let privateExponent = rsaTestPrivateExponent()
    let ciphertext      = rsaTestHexBytes("3a76e6e70a237da35585db6caa002e5042c0c857a5a8bd76bfd96480bdceefc00870edc9bd0a01e0d2bff0f47f5703614656f9644c25f54a75ceffd6e7c2404857f272fa1b163cecf253fea2539995e2e4b90fec14f88f9a7cb54fb7a1f916fd59454b51e784b68b0d3e3e4565ff811edb484f296094dacb63fef72a4cbbf12b3053e50f8dc705d608563263c5b2e461865b9e43da1796ef6e65639b5809f7c56759e7371c88d79b22a2f758b9253e3ae8283ff5abb2275823662c800587231cb1e0a15d9937570809af6b823df4d21cc45c1ab30828741d4eca4fdec84b54b67ea052509ebc12863bb6987062f2f92e8425aea67634ca284cf225d2d338d12c")
    var plaintext: [256] u8
    let length          = expect Crypto.rsaOaepSha256Decrypt(modulus.toSlice(), privateExponent.toSlice(), ciphertext.toSlice(), "swag-rsa-label", plaintext)
    Swag.require(Crypto.constantTimeEqual(plaintext[0 until length], "RSA OAEP interoperability"))

    var untouched: [256] u8
    Swag.memset(&untouched[0], 0xA5, untouched.count)
    var error: Swag.Error
    discard catch Crypto.rsaOaepSha256Decrypt(modulus.toSlice(), privateExponent.toSlice(), ciphertext.toSlice(), "wrong label", untouched) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in untouched do
        Swag.require(byte == 0xA5)

    var outOfRange: [256] u8
    Swag.memset(&outOfRange[0], 0xFF, outOfRange.count)
    var rangeError: Swag.Error
    discard catch Crypto.rsaOaepSha256Decrypt(modulus.toSlice(), privateExponent.toSlice(), outOfRange, "swag-rsa-label", untouched) as rangeError
    Swag.require(rangeError.value() is Errors.BadParameterError)
}

#test
{
    let modulus                = rsaTestModulus()
    let privateExponent        = rsaTestPrivateExponent()
    let publicExponent: [3] u8 = [1, 0, 1]
    let plaintext              = "round-trip OAEP"
    var ciphertext:     [256] u8
    expect Crypto.rsaOaepSha256Encrypt(modulus.toSlice(), publicExponent, plaintext, "context", ciphertext)
    var decrypted: [256] u8
    let length = expect Crypto.rsaOaepSha256Decrypt(modulus.toSlice(), privateExponent.toSlice(), ciphertext, "context", decrypted)
    Swag.require(Crypto.constantTimeEqual(decrypted[0 until length], plaintext))

    var oversized: [191] u8
    var error:     Swag.Error
    discard catch Crypto.rsaOaepSha256Encrypt(modulus.toSlice(), publicExponent, oversized, "", ciphertext) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    // OpenSSL verifies this PSS-SHA-256 signature with its fixed 32-byte salt.
    let modulus   = rsaTestModulus()
    let publicExponent: [3] u8 = [1, 0, 1]
    var signature = rsaTestHexBytes("618286ac498bd2e547ce8dc055aaf0f42a1b8c54f6e4a884ca99c3f1d5297810417f76cbb0686bd535631c567bf1f2dd21f8b1c80b72ee48074539bfc2337b156af7d12694d4326029801b5716a6ab45f2c45323d0f1bdcaa2c5056c21f47fec958ac500bfa5357cb8fe9667528f7e303d3ab0e42c4a5664331eec7e79ca704e7614dd30a85b5fab1e7ab3124232556b0b116cee7aae7d15b8491d9a8473a1941a51c5d1c51868367e2f2c194e4f295f0d32caf094d1e42051103e8a9255eb4157c4cf79ba16d9abae95593eb3f101b58cb8ac9a4c94642344cbc0ee80726fdc8f5e98a2353fe5bc3b1fdb768b514f3e27248be3ca07f2e1293a170ec5b609a0")
    Swag.require(expect Crypto.rsaPssSha256Verify(modulus.toSlice(), publicExponent, "RSA PSS interoperability", signature.toSlice()))
    Swag.require(not expect Crypto.rsaPssSha256Verify(modulus.toSlice(), publicExponent, "wrong message", signature.toSlice()))
    signature[0] ^= 1
    Swag.require(not expect Crypto.rsaPssSha256Verify(modulus.toSlice(), publicExponent, "RSA PSS interoperability", signature.toSlice()))
}

#test
{
    let modulus                = rsaTestModulus()
    let privateExponent        = rsaTestPrivateExponent()
    let publicExponent: [3] u8 = [1, 0, 1]
    var signature:      [256] u8
    expect Crypto.rsaPssSha256Sign(modulus.toSlice(), privateExponent.toSlice(), "generated PSS signature", signature)
    Swag.require(expect Crypto.rsaPssSha256Verify(modulus.toSlice(), publicExponent, "generated PSS signature", signature))
    Swag.require(not expect Crypto.rsaPssSha256Verify(modulus.toSlice(), publicExponent, "altered PSS message", signature))
}

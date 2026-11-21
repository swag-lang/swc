#global if #command == Swag.CompilerCommand.Test
#global private

func ed25519HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func ed25519HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (ed25519HexDigit(text[index]) << 4) | ed25519HexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // RFC 8032 Section 7.1, test vector 1: empty message.
    let seed = ed25519HexBytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    let expectedPublic    = ed25519HexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
    let expectedSignature = ed25519HexBytes("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    var publicKey: [32] u8
    var signature: [64] u8
    expect Crypto.ed25519PublicKey(seed.toSlice(), publicKey)
    expect Crypto.ed25519Sign(seed.toSlice(), "", signature)
    Swag.require(Crypto.constantTimeEqual(publicKey, expectedPublic.toSlice()))
    Swag.require(Crypto.constantTimeEqual(signature, expectedSignature.toSlice()))
    Swag.require(expect Crypto.ed25519Verify(publicKey, "", signature))

    Swag.require(not (expect Crypto.ed25519Verify(publicKey, "changed", signature)))

    var noncanonicalPublic: [32] u8
    noncanonicalPublic[0] = 0xED
    for index in 1 until 31 do
        noncanonicalPublic[index] = 0xFF
    noncanonicalPublic[31] = 0x7F
    Swag.require(not (expect Crypto.ed25519Verify(noncanonicalPublic, "", signature)))

    var noncanonicalR = signature
    noncanonicalR[0] = 0xED
    for index in 1 until 31 do
        noncanonicalR[index] = 0xFF
    noncanonicalR[31] = 0x7F
    Swag.require(not (expect Crypto.ed25519Verify(publicKey, "", noncanonicalR)))

    var shortSignature: [63] u8
    var lengthError:    Swag.Error
    discard catch Crypto.ed25519Verify(publicKey, "", shortSignature) as lengthError
    Swag.require(lengthError.value() is Errors.BadParameterError)
}

#test
{
    let seed              = ed25519HexBytes("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
    let message           = ed25519HexBytes("72")
    let expectedPublic    = ed25519HexBytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
    let expectedSignature = ed25519HexBytes("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
    var signature: [64] u8
    expect Crypto.ed25519Sign(seed.toSlice(), message.toSlice(), signature)
    var publicKey: [32] u8
    expect Crypto.ed25519PublicKey(seed.toSlice(), publicKey)
    Swag.require(Crypto.constantTimeEqual(publicKey, expectedPublic.toSlice()))
    Swag.require(Crypto.constantTimeEqual(signature, expectedSignature.toSlice()))
    Swag.require(expect Crypto.ed25519Verify(publicKey, message.toSlice(), signature))

    var invalidSignature = signature
    for index in 32 to 64 do
        invalidSignature[index] = 0xFF
    Swag.require(not (expect Crypto.ed25519Verify(publicKey, message.toSlice(), invalidSignature)))
    Swag.require(not (expect Crypto.ed25519Verify(publicKey, "wrong message", signature)))
}

#test
{
    var shortSeed:      [31] u8
    var publicKey:      [32] u8
    var signature:      [64] u8
    var publicKeyError: Swag.Error
    discard catch Crypto.ed25519PublicKey(shortSeed, publicKey) as publicKeyError
    Swag.require(publicKeyError.value() is Errors.BadParameterError)

    var signError: Swag.Error
    discard catch Crypto.ed25519Sign(shortSeed, "message", signature) as signError
    Swag.require(signError.value() is Errors.BadParameterError)
}

#test
{
    // Independent OpenSSL-compatible vector for a multi-block SHA-512 message.
    var seed: [32] u8
    for index in 32 do
        seed[index] = cast(u8, index)
    var message: Array'u8
    for index in 512 do
        message.add(cast(u8, index))

    let expectedPublic    = ed25519HexBytes("03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8")
    let expectedSignature = ed25519HexBytes("2635e190571f5dd9181726441e24f22ade35c30a2dff36626183d1e87cd2b99b3618d46fb5929246962762e392efbef8ef566b3270dc5a10b5435caddd70fc04")
    var publicKey: [32] u8
    var signature: [64] u8
    expect Crypto.ed25519PublicKey(seed, publicKey)
    expect Crypto.ed25519Sign(seed, message.toSlice(), signature)
    Swag.require(Crypto.constantTimeEqual(publicKey, expectedPublic.toSlice()))
    Swag.require(Crypto.constantTimeEqual(signature, expectedSignature.toSlice()))
    Swag.require(expect Crypto.ed25519Verify(publicKey, message.toSlice(), signature))
}

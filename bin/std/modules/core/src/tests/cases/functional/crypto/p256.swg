#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func p256HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func p256HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((p256HexDigit(text[index]) << 4) | p256HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    var scalarOne: [Crypto.P256ScalarSize] u8
    scalarOne[31] = 1
    var scalarTwo: [Crypto.P256ScalarSize] u8
    scalarTwo[31] = 2
    let expectedGenerator = p256HexBytes("046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
    let expectedDouble    = p256HexBytes("047cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1")

    var publicOne: [Crypto.P256PublicKeySize] u8
    var publicTwo: [Crypto.P256PublicKeySize] u8
    expect Crypto.p256PublicKey(scalarOne, publicOne)
    expect Crypto.p256PublicKey(scalarTwo, publicTwo)
    Swag.require(Crypto.constantTimeEqual(publicOne, expectedGenerator.toSlice()))
    Swag.require(Crypto.constantTimeEqual(publicTwo, expectedDouble.toSlice()))

    var sharedOne: [Crypto.P256ScalarSize] u8
    var sharedTwo: [Crypto.P256ScalarSize] u8
    expect Crypto.p256Ecdh(scalarOne, publicTwo, sharedOne)
    expect Crypto.p256Ecdh(scalarTwo, publicOne, sharedTwo)
    Swag.require(Crypto.constantTimeEqual(sharedOne, expectedDouble[1 until 33]))
    Swag.require(Crypto.constantTimeEqual(sharedTwo, sharedOne))
}

#test
{
    var scalarTwo:   [Crypto.P256ScalarSize] u8
    var scalarThree: [Crypto.P256ScalarSize] u8
    scalarTwo[31]   = 2
    scalarThree[31] = 3
    let expectedThree  = p256HexBytes("045ecbe4d1a6330a44c8f7ef951d4bf165e6c6b721efada985fb41661bc6e7fd6c8734640c4998ff7e374b06ce1a64a2ecd82ab036384fb83d9a79b127a27d5032")
    let expectedShared = p256HexBytes("b01a172a76a4602c92d3242cb897dde3024c740debb215b4c6b0aae93c2291a9")

    var publicTwo:   [Crypto.P256PublicKeySize] u8
    var publicThree: [Crypto.P256PublicKeySize] u8
    expect Crypto.p256PublicKey(scalarTwo, publicTwo)
    expect Crypto.p256PublicKey(scalarThree, publicThree)
    Swag.require(Crypto.constantTimeEqual(publicThree, expectedThree.toSlice()))

    var sharedOne: [Crypto.P256ScalarSize] u8
    var sharedTwo: [Crypto.P256ScalarSize] u8
    expect Crypto.p256Ecdh(scalarTwo, publicThree, sharedOne)
    expect Crypto.p256Ecdh(scalarThree, publicTwo, sharedTwo)
    Swag.require(Crypto.constantTimeEqual(sharedOne, expectedShared.toSlice()))
    Swag.require(Crypto.constantTimeEqual(sharedTwo, expectedShared.toSlice()))
}

#test
{
    let privateKey        = p256HexBytes("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
    let expectedPublic    = p256HexBytes("0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299")
    let expectedSignature = p256HexBytes("efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8")
    var publicKey: [Crypto.P256PublicKeySize] u8
    var signature: [64] u8
    expect Crypto.p256PublicKey(privateKey.toSlice(), publicKey)
    Swag.require(Crypto.constantTimeEqual(publicKey, expectedPublic.toSlice()))

    expect Crypto.p256EcdsaSign(privateKey.toSlice(), "sample", signature)
    Swag.require(Crypto.constantTimeEqual(signature, expectedSignature.toSlice()))
    var repeatedSignature: [64] u8
    expect Crypto.p256EcdsaSign(privateKey.toSlice(), "sample", repeatedSignature)
    Swag.require(Crypto.constantTimeEqual(signature, repeatedSignature))
    let verified     = expect Crypto.p256EcdsaVerify(publicKey, "sample", signature)
    let wrongMessage = expect Crypto.p256EcdsaVerify(publicKey, "Sample", signature)
    Swag.require(verified and not wrongMessage)
    signature[63] ^= 1
    let tampered = expect Crypto.p256EcdsaVerify(publicKey, "sample", signature)
    Swag.require(not tampered)
    var invalidSignature: [64] u8
    let invalid = expect Crypto.p256EcdsaVerify(publicKey, "sample", invalidSignature)
    Swag.require(not invalid)
}

#test
{
    let scalarBytes = p256HexBytes("519b423d715f8b5d549cf123456789abcdef0123456789abcdef0123456789ab")
    let expected    = p256HexBytes("04a06cc8dd2d8b26db5fc4229bc1bb0f4042e393a0c7e7fb7a12d7aed0131d9c06b37d3e9614891f7d1fa727e8a4c1c26e00e035103a18131b00797c6e7acd57e6")
    var publicKey: [Crypto.P256PublicKeySize] u8
    expect Crypto.p256PublicKey(scalarBytes.toSlice(), publicKey)
    Swag.require(Crypto.constantTimeEqual(publicKey, expected.toSlice()))
}

#test
{
    var zeroScalar: [Crypto.P256ScalarSize] u8
    var output:     [Crypto.P256PublicKeySize] u8
    var error:      Swag.Error
    discard catch Crypto.p256PublicKey(zeroScalar, output) as error
    Swag.require(error.value() is Errors.BadParameterError)

    let scalarOrder = p256HexBytes("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")
    discard catch Crypto.p256PublicKey(scalarOrder.toSlice(), output) as error
    Swag.require(error.value() is Errors.BadParameterError)

    var generator: [Crypto.P256PublicKeySize] u8
    generator[0] = 4
    let coordinates = p256HexBytes("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
    Swag.memcpy(&generator[1], &coordinates[0], coordinates.count)
    generator[64] ^= 1
    var shared: [Crypto.P256ScalarSize] u8
    var one:    [Crypto.P256ScalarSize] u8
    one[31] = 1
    discard catch Crypto.p256Ecdh(one, generator, shared) as error
    Swag.require(error.value() is Errors.BadParameterError)

    generator[64] ^= 1
    let fieldModulus = p256HexBytes("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
    Swag.memcpy(&generator[1], &fieldModulus[0], fieldModulus.count)
    discard catch Crypto.p256Ecdh(one, generator, shared) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

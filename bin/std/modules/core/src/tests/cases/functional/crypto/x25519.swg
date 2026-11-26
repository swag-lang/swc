#global if #command == Swag.CompilerCommand.Test
#global private

func x25519HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func x25519HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (x25519HexDigit(text[index]) << 4) | x25519HexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // RFC 7748 Section 6.1 public-key examples for Alice and Bob.
    let alicePrivate = x25519HexBytes("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    let bobPrivate   = x25519HexBytes("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    let alicePublic  = x25519HexBytes("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    let bobPublic    = x25519HexBytes("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    var actualAlice: [32] u8
    var actualBob:   [32] u8
    expect Crypto.x25519PublicKey(alicePrivate.toSlice(), actualAlice)
    expect Crypto.x25519PublicKey(bobPrivate.toSlice(), actualBob)
    Swag.require(Crypto.constantTimeEqual(actualAlice, alicePublic.toSlice()))
    Swag.require(Crypto.constantTimeEqual(actualBob, bobPublic.toSlice()))

    var clampingVariant = alicePrivate
    clampingVariant[0]  ^= 7
    clampingVariant[31] ^= 0xC0
    var variantPublic: [32] u8
    expect Crypto.x25519PublicKey(clampingVariant.toSlice(), variantPublic)
    Swag.require(Crypto.constantTimeEqual(actualAlice, variantPublic))

    var inPlace = alicePrivate
    expect Crypto.x25519PublicKey(inPlace.toSlice(), inPlace.toSlice())
    Swag.require(Crypto.constantTimeEqual(inPlace.toSlice(), alicePublic.toSlice()))
}

#test
{
    // Both peers derive the same RFC 7748 shared secret.
    let alicePrivate = x25519HexBytes("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    let bobPrivate   = x25519HexBytes("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    let alicePublic  = x25519HexBytes("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    let bobPublic    = x25519HexBytes("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    let expected     = x25519HexBytes("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    var aliceSecret: [32] u8
    var bobSecret:   [32] u8
    expect Crypto.x25519SharedSecret(alicePrivate.toSlice(), bobPublic.toSlice(), aliceSecret)
    expect Crypto.x25519SharedSecret(bobPrivate.toSlice(), alicePublic.toSlice(), bobSecret)
    Swag.require(Crypto.constantTimeEqual(aliceSecret, expected.toSlice()))
    Swag.require(Crypto.constantTimeEqual(aliceSecret, bobSecret))

    var highBitCoordinate = bobPublic
    highBitCoordinate[31] |= 0x80
    var highBitSecret: [32] u8
    expect Crypto.x25519SharedSecret(alicePrivate.toSlice(), highBitCoordinate.toSlice(), highBitSecret)
    Swag.require(Crypto.constantTimeEqual(aliceSecret, highBitSecret))
}

#test
{
    var privateKey: [32] u8
    var lowOrder:   [32] u8
    var result:     [32] u8
    var error:      Swag.Error
    discard catch Crypto.x25519SharedSecret(privateKey, lowOrder, result) as error
    Swag.require(error.value() is Errors.BadParameterError)

    lowOrder[0] = 1
    var oneLowOrderError: Swag.Error
    discard catch Crypto.x25519SharedSecret(privateKey, lowOrder, result) as oneLowOrderError
    Swag.require(oneLowOrderError.value() is Errors.BadParameterError)

    var shortKey:    [31] u8
    var lengthError: Swag.Error
    discard catch Crypto.x25519PublicKey(shortKey, result) as lengthError
    Swag.require(lengthError.value() is Errors.BadParameterError)
}

// RFC 7748 section 5.2 iterates X25519 on each previous result.
#test
{
    let first      = x25519HexBytes("422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079")
    let thousandth = x25519HexBytes("684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51")
    var key: [32] u8
    key[0] = 9
    var coordinate = key
    for iteration in 1000
    {
        var next: [32] u8
        expect Crypto.x25519SharedSecret(key, coordinate, next)
        coordinate = key
        key        = next
        if iteration == 0 do
            Swag.require(Crypto.constantTimeEqual(key, first.toSlice()))
    }

    Swag.require(Crypto.constantTimeEqual(key, thousandth.toSlice()))
}

// RFC 7748 accepts an input that is noncanonical modulo 2^255 - 19.
#test
{
    var scalar:   [32] u8
    let noncanonical = x25519HexBytes("f6ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")
    var expected: [32] u8
    var actual:   [32] u8
    expect Crypto.x25519PublicKey(scalar, expected)
    expect Crypto.x25519SharedSecret(scalar, noncanonical.toSlice(), actual)
    Swag.require(Crypto.constantTimeEqual(expected, actual))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesXtsHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesXtsHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesXtsHexDigit(text[index]) << 4) | aesXtsHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // AES-128-XTS ciphertext stealing vector, cross-checked with OpenSSL EVP XTS.
    let key       = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let tweak     = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f")
    let plaintext = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let expected  = aesXtsHexBytes("6893fb9867b3982bf0415031253b1cacb62412371f8d7cf1e27c05af1a83d9")
    var ciphertext: [31] u8
    expect Crypto.aesXtsCrypt(key.toSlice(), tweak.toSlice(), plaintext.toSlice(), ciphertext, false)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected.toSlice()))
    expect Crypto.aesXtsCrypt(key.toSlice(), tweak.toSlice(), ciphertext, ciphertext, true)
    Swag.require(Crypto.constantTimeEqual(ciphertext, plaintext.toSlice()))
}

#test
{
    // AES-256-XTS verifies the other standard combined key size over full blocks.
    let key      = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f")
    let tweak    = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f")
    let data     = aesXtsHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let expected = aesXtsHexBytes("b82298441f93d2a0ad34668c7df66e4c9ce4d6a936a41f0f8983a38c00a32efd")
    var output: [32] u8
    expect Crypto.aesXtsCrypt(key.toSlice(), tweak.toSlice(), data.toSlice(), output, false)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))
    expect Crypto.aesXtsCrypt(key.toSlice(), tweak.toSlice(), output, output, true)
    Swag.require(Crypto.constantTimeEqual(output, data.toSlice()))
}

#test
{
    // OpenSSL EVP XTS vector over two groups of four blocks and a stolen final byte.
    let key = #stringof("0123456789abcdefghijklmnopqrstuv", "vutsrqponmlkjihgfedcba9876543210")
    let expected = aesXtsHexBytes(#stringof(
        "6fdd01b99ad3db1052fbee3c26842937d6da671e360e5f32d5ba3ba463c2f25d",
        "a588ff2057d1b34357b82562a141b2e725bf347707d851508733c416adb9b122",
        "4c0e115d99478ed45c34238c1b6537e1e3b9f7b36ea225846393b9e432c2e2ff",
        "c5f40c2ab7627043df834ffda2708412153932b5f1c86ed1102bfc0802c4f41b",
        "4354f7ffb7803a7f47d277574401b799a7"))
    var storage: [147] u8
    storage[0] = 0xA5
    storage[146] = 0x5A
    let data = storage[1 until 146]
    for index in data.count do
        data[index] = cast(u8, (index * 13 + 7) & 0xFF)

    expect Crypto.aesXtsCrypt(key, "0123456789abcdef", data, data, false)
    Swag.require(Crypto.constantTimeEqual(data, expected.toSlice()))
    expect Crypto.aesXtsCrypt(key, "0123456789abcdef", data, data, true)
    for index in data.count do
        Swag.require(data[index] == cast(u8, (index * 13 + 7) & 0xFF))
    Swag.require(storage[0] == 0xA5 and storage[146] == 0x5A)
}

#test
{
    var key:    [32] u8
    var tweak:  [Crypto.AesXtsTweakSize] u8
    var input:  [15] u8
    var output: [15] u8
    var error:  Swag.Error
    discard catch Crypto.aesXtsCrypt(key, tweak, input, output, false) as error
    Swag.require(error.value() is Errors.BadParameterError)

    var shortKey: [48] u8
    var block:    [16] u8
    discard catch Crypto.aesXtsCrypt(shortKey, tweak, block, block, false) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

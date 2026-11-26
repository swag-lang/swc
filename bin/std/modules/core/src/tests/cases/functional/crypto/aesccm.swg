#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesCcmHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesCcmHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesCcmHexDigit(text[index]) << 4) | aesCcmHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // RFC 3610 packet vector 1 covers the short nonce, encoded associated data, and 64-bit tag.
    let key                = aesCcmHexBytes("c0c1c2c3c4c5c6c7c8c9cacbcccdcecf")
    let nonce              = aesCcmHexBytes("00000003020100a0a1a2a3a4a5")
    let associatedData     = aesCcmHexBytes("0001020304050607")
    let plaintext          = aesCcmHexBytes("08090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let expectedCiphertext = aesCcmHexBytes("588c979a61c663d2f066d0c2c0f989806d5f6b61dac384")
    let expectedTag        = aesCcmHexBytes("17e8d12cfdf926e0")
    var ciphertext: [23] u8
    var tag:        [8] u8
    expect Crypto.aesCcmEncrypt(key.toSlice(), nonce.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expectedCiphertext.toSlice()))
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))
    expect Crypto.aesCcmDecrypt(key.toSlice(), nonce.toSlice(), associatedData.toSlice(), ciphertext, tag, ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, plaintext.toSlice()))
}

#test
{
    // AES-128/192/256 use the 7-byte nonce limit and a full 128-bit authentication tag.
    let key128         = aesCcmHexBytes("000102030405060708090a0b0c0d0e0f")
    let key192         = aesCcmHexBytes("000102030405060708090a0b0c0d0e0f1011121314151617")
    let key256         = aesCcmHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce          = aesCcmHexBytes("00010203040506")
    let associatedData = aesCcmHexBytes("000102030405060708090a0b0c0d0e0f101112")
    let plaintext      = aesCcmHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let expected128    = aesCcmHexBytes("5715b1ef39830708a405a5ee98eb09b0cf21098c7b865325998ba6e70eb59e5c409f016042a352880bd5e97e2af047")
    let expected192    = aesCcmHexBytes("9568aba9f7d899f495ee8ec0e4c15754d030d98affc1f7f139ba8599efe1a5e7a7c99246749c3605db08a08b66a9bc")
    let expected256    = aesCcmHexBytes("9ff08efc978590fa264a27f52ec35dab4088b916b7a223c3904601900d495107d833802dc40159e7de373d2fb3df45")
    var ciphertext: [31] u8
    var tag:        [16] u8
    expect Crypto.aesCcmEncrypt(key128.toSlice(), nonce.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected128[until 31]))
    Swag.require(Crypto.constantTimeEqual(tag, expected128[31 until]))
    expect Crypto.aesCcmEncrypt(key192.toSlice(), nonce.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected192[until 31]))
    Swag.require(Crypto.constantTimeEqual(tag, expected192[31 until]))
    expect Crypto.aesCcmEncrypt(key256.toSlice(), nonce.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected256[until 31]))
    Swag.require(Crypto.constantTimeEqual(tag, expected256[31 until]))
}

#test
{
    // Four-byte tags are supported, while invalid parameters and bad tags fail cleanly.
    var key:         [16] u8
    var nonce:       [7] u8
    var empty:       Array'u8
    var emptyOutput: Array'u8
    var tag:         [4] u8
    let expectedTag = aesCcmHexBytes("5863e479")
    expect Crypto.aesCcmEncrypt(key, nonce, "", empty.toSlice(), emptyOutput.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    var plaintext:  [8] u8
    var ciphertext: [8] u8
    var largeTag:   [16] u8
    expect Crypto.aesCcmEncrypt(key, nonce, "", plaintext, ciphertext, largeTag)
    largeTag[0] ^= 1
    Memory.set(plaintext.buffer, 0xA5'u8, plaintext.count)
    var error: Swag.Error
    discard catch Crypto.aesCcmDecrypt(key, nonce, "", ciphertext, largeTag, plaintext) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in plaintext do
        Swag.require(byte == 0xA5)

    var invalidNonce: [6] u8
    discard catch Crypto.aesCcmEncrypt(key, invalidNonce, "", plaintext, ciphertext, largeTag) as error
    Swag.require(error.value() is Errors.BadParameterError)

    var longNonce: [13] u8
    var oversized: Array'u8
    oversized.resize(65536)
    var oversizedCiphertext: Array'u8
    oversizedCiphertext.resize(oversized.count)
    discard catch Crypto.aesCcmEncrypt(key, longNonce, "", oversized.toSlice(), oversizedCiphertext.toSlice(), largeTag) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    // OpenSSL EVP vector for the shortest counter field, batched CTR and a partial block.
    const Key = "0123456789abcdefghijklmnopqrstuv"
    const Aad = "swag-crypto-1"
    let nonce = aesCcmHexBytes("ffffffffffffffffffffffffff")
    let expected = aesCcmHexBytes(#stringof(
        "2fe735f45c7a860659e3f35f431d9188b4341baabcd4a4e6887adb0f38bc74be",
        "d984612790d09abd69fc3f390d0d30821d3d3a0eb855ed4864480987082560e9",
        "f9098b8e5129bf5b62d77ce06e2f5fcbaee54f663815977231c17c8881ffe77f",
        "3ce8f51d830b25a68f316f492ff4516bb16187fac05907dbf92ac0de53f9609f",
        "9edf8543069332eeb588cd4a72309bf13b"))
    let expectedTag = aesCcmHexBytes("1e17d7d418e585b66ee97c59585c5051")
    var storage: [147] u8
    var tag: [Crypto.AesCcmTagMaxSize] u8
    storage[0] = 0xA5
    storage[146] = 0x5A
    let data = storage[1 until 146]
    for index in data.count do
        data[index] = cast(u8, (index * 13 + 7) & 0xFF)

    expect Crypto.aesCcmEncrypt(Key, nonce.toSlice(), Aad, data, data, tag)
    Swag.require(Crypto.constantTimeEqual(data, expected.toSlice()))
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    tag[0] ^= 1
    var error: Swag.Error
    discard catch Crypto.aesCcmDecrypt(Key, nonce.toSlice(), Aad, data, tag, data) as error
    Swag.require(error.value() is Errors.BadParameterError)
    Swag.require(Crypto.constantTimeEqual(data, expected.toSlice()))
    tag[0] ^= 1

    expect Crypto.aesCcmDecrypt(Key, nonce.toSlice(), Aad, data, tag, data)
    for index in data.count do
        Swag.require(data[index] == cast(u8, (index * 13 + 7) & 0xFF))
    Swag.require(storage[0] == 0xA5 and storage[146] == 0x5A)
}

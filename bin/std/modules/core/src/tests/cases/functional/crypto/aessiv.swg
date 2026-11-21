#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesSivHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesSivHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesSivHexDigit(text[index]) << 4) | aesSivHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // AES-128-SIV vectors cross-checked with OpenSSL EVP through the AESSIV interface.
    let key             = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let plaintext       = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let associatedData  = aesSivHexBytes("000102030405060708090a0b0c0d0e0f10111213141516")
    let shortPlaintext  = aesSivHexBytes("000102030405060708090a0b0c0d0e")
    let expectedNoAd    = aesSivHexBytes("ecd1ab8023140fcdb76cf7e9bf006071c03abd6183bc4f32b8650ebed4c59b2353507669f5e26365d86dc426075897")
    let expectedAd      = aesSivHexBytes("0b4bc85c55a2d9dd1dba3cab123436fd2b376121d2db8869ae8213686d4c6a24643f96f1469fb5d8747147d106da6c")
    let expectedShortAd = aesSivHexBytes("76b398adee6ed362bd1aa499dc0ddfdedadc6ce5526e5ba74099827c4622eb")
    var ciphertext: [31] u8
    var tag:        [Crypto.AesSivTagSize] u8
    expect Crypto.aesSivEncrypt(key.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(tag, expectedNoAd[until 16]))
    Swag.require(Crypto.constantTimeEqual(ciphertext, expectedNoAd[16 until]))
    expect Crypto.aesSivDecrypt(key.toSlice(), ciphertext, tag, ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, plaintext.toSlice()))

    expect Crypto.aesSivEncryptWithAssociatedData(key.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(tag, expectedAd[until 16]))
    Swag.require(Crypto.constantTimeEqual(ciphertext, expectedAd[16 until]))
    var decrypted: [31] u8
    expect Crypto.aesSivDecryptWithAssociatedData(key.toSlice(), associatedData.toSlice(), ciphertext, tag, decrypted)
    Swag.require(Crypto.constantTimeEqual(decrypted, plaintext.toSlice()))

    var shortCiphertext: [15] u8
    expect Crypto.aesSivEncryptWithAssociatedData(key.toSlice(), associatedData.toSlice(), shortPlaintext.toSlice(), shortCiphertext, tag)
    Swag.require(Crypto.constantTimeEqual(tag, expectedShortAd[until 16]))
    Swag.require(Crypto.constantTimeEqual(shortCiphertext, expectedShortAd[16 until]))
}

#test
{
    // AES-192-SIV and AES-256-SIV use independent equal-length MAC and CTR keys.
    let key192         = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")
    let key256         = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f")
    let plaintext      = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let associatedData = aesSivHexBytes("000102030405060708090a0b0c0d0e0f10111213141516")
    let expected192    = aesSivHexBytes("4b5fa5c0947d5a1fdc50bd5bce75bd12b8052b9c13794a5d5e87ce834a1775cfd47bc8fe0d25056da05c6e0497c89a")
    let expected256    = aesSivHexBytes("2698e73f01bf0481c86c079f76f83cb65e9f9e53e5ee64fe5d81528d4518e1bddb354b2a9491277eced6d1ee098932")
    var ciphertext: [31] u8
    var tag:        [Crypto.AesSivTagSize] u8
    expect Crypto.aesSivEncryptWithAssociatedData(key192.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(tag, expected192[until 16]))
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected192[16 until]))
    expect Crypto.aesSivEncryptWithAssociatedData(key256.toSlice(), associatedData.toSlice(), plaintext.toSlice(), ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(tag, expected256[until 16]))
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected256[16 until]))
}

#test
{
    // No associated data, an empty message, and authentication failure preserve the destination.
    let key         = aesSivHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let expectedTag = aesSivHexBytes("6890e5685ed0253753a2121dab850fdf")
    var empty: Array'u8
    var emptyCiphertext: Array'u8
    var tag:   [Crypto.AesSivTagSize] u8
    expect Crypto.aesSivEncrypt(key.toSlice(), empty.toSlice(), emptyCiphertext.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    var plaintext:  [8] u8
    var ciphertext: [8] u8
    expect Crypto.aesSivEncrypt(key.toSlice(), plaintext, ciphertext, tag)
    tag[0] ^= 1
    Memory.set(plaintext.buffer, 0xA5'u8, plaintext.count)
    var error: Swag.Error
    discard catch Crypto.aesSivDecrypt(key.toSlice(), ciphertext, tag, plaintext) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in plaintext do
        Swag.require(byte == 0xA5)

    var associatedData: [4] u8
    var authenticatedCiphertext: [8] u8
    expect Crypto.aesSivEncryptWithAssociatedData(key.toSlice(), associatedData, ciphertext, authenticatedCiphertext, tag)
    associatedData[0] ^= 1
    discard catch Crypto.aesSivDecryptWithAssociatedData(key.toSlice(), associatedData, authenticatedCiphertext, tag, plaintext) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in plaintext do
        Swag.require(byte == 0xA5)
}

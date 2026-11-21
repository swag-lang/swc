#global if #command == Swag.CompilerCommand.Test
#global private

func aesGcmHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesGcmHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (aesGcmHexDigit(text[index]) << 4) | aesGcmHexDigit(text[index + 1])))
        index += 2
    }

    return result
}

#test
{
    // NIST SP 800-38D, Test Case 1: empty plaintext and associated data.
    var key:   [16] u8
    var nonce: [12] u8
    var tag:   [16] u8
    var empty: Array'u8
    let expected = aesGcmHexBytes("58e2fccefa7e3061367f1d57a4e7455a")
    expect Crypto.aesGcmEncrypt(key, nonce, "", "", empty.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(tag, expected.toSlice()))
}

#test
{
    // NIST SP 800-38D empty-message vectors cover the other supported AES key sizes.
    var nonce: [12] u8
    var tag:   [16] u8
    var empty: Array'u8
    let expected192 = aesGcmHexBytes("cd33b28ac773f74ba00ed1f312572435")
    let expected256 = aesGcmHexBytes("530f8afbc74536b9a963b4f1c4cb738b")
    let key192      = aesGcmHexBytes("000000000000000000000000000000000000000000000000")
    let key256      = aesGcmHexBytes("0000000000000000000000000000000000000000000000000000000000000000")
    expect Crypto.aesGcmEncrypt(key192.toSlice(), nonce, "", "", empty.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(tag, expected192.toSlice()))
    expect Crypto.aesGcmEncrypt(key256.toSlice(), nonce, "", "", empty.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(tag, expected256.toSlice()))
}

#test
{
    // NIST SP 800-38D, Test Case 2: one zero block with the all-zero AES-128 key and nonce.
    var key:        [16] u8
    var nonce:      [12] u8
    var plaintext:  [16] u8
    var ciphertext: [16] u8
    var tag:        [16] u8
    let expectedCiphertext = aesGcmHexBytes("0388dace60b6a392f328c2b971b2fe78")
    let expectedTag        = aesGcmHexBytes("ab6e47d42cec13bdf53a67b21257bddf")
    expect Crypto.aesGcmEncrypt(key, nonce, "", plaintext, ciphertext, tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expectedCiphertext.toSlice()))
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    var decrypted: [16] u8
    expect Crypto.aesGcmDecrypt(key, nonce, "", ciphertext, tag, decrypted)
    Swag.require(Crypto.constantTimeEqual(decrypted, plaintext))
}

#test
{
    // Exact in-place encryption and decryption preserve the 16-byte NIST result.
    var key:   [16] u8
    var nonce: [12] u8
    var block: [16] u8
    var tag:   [16] u8
    let expectedCiphertext = aesGcmHexBytes("0388dace60b6a392f328c2b971b2fe78")
    expect Crypto.aesGcmEncrypt(key, nonce, "", block, block, tag)
    Swag.require(Crypto.constantTimeEqual(block, expectedCiphertext.toSlice()))
    expect Crypto.aesGcmDecrypt(key, nonce, "", block, tag, block)
    var zeroBlock: [16] u8
    Swag.require(Crypto.constantTimeEqual(block, zeroBlock))
}

#test
{
    // NIST SP 800-38D, Test Case 3 exercises partial final blocks and authenticated data.
    let key                = aesGcmHexBytes("feffe9928665731c6d6a8f9467308308")
    let nonce              = aesGcmHexBytes("cafebabefacedbaddecaf888")
    var aad                = aesGcmHexBytes("feedfacedeadbeeffeedfacedeadbeefabaddad2")
    let plaintext          = aesGcmHexBytes("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
    let expectedCiphertext = aesGcmHexBytes("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091")
    let expectedTag        = aesGcmHexBytes("5bc94fbc3221a5db94fae95ae7121a47")
    var ciphertext: Array'u8
    ciphertext.resize(plaintext.count)
    var tag: [16] u8
    expect Crypto.aesGcmEncrypt(key.toSlice(), nonce.toSlice(), aad.toSlice(), plaintext.toSlice(), ciphertext.toSlice(), tag)
    Swag.require(Crypto.constantTimeEqual(ciphertext.toSlice(), expectedCiphertext.toSlice()))
    Swag.require(Crypto.constantTimeEqual(tag, expectedTag.toSlice()))

    var decrypted: Array'u8
    decrypted.resize(plaintext.count)
    expect Crypto.aesGcmDecrypt(key.toSlice(), nonce.toSlice(), aad.toSlice(), ciphertext.toSlice(), tag, decrypted.toSlice())
    Swag.require(Crypto.constantTimeEqual(decrypted.toSlice(), plaintext.toSlice()))

    var destination: Array'u8
    destination.resize(plaintext.count)
    Swag.memset(&destination[0], 0xA5, destination.count)
    aad[0] ^= 1
    var error: Swag.Error
    discard catch Crypto.aesGcmDecrypt(key.toSlice(), nonce.toSlice(), aad.toSlice(), ciphertext.toSlice(), tag, destination.toSlice()) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in destination.toSlice() do
        Swag.require(byte == 0xA5)
}

#test
{
    var key:         [16] u8
    var nonce:       [12] u8
    var ciphertext:  [16] u8
    var tag:         [16] u8
    var destination: [16] u8
    Swag.memset(&destination[0], 0xA5, destination.count)
    var error: Swag.Error
    discard catch Crypto.aesGcmDecrypt(key, nonce, "", ciphertext, tag, destination) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for byte in destination do
        Swag.require(byte == 0xA5)

    var shortNonce: [11] u8
    var empty:      Array'u8
    var sizeError:  Swag.Error
    discard catch Crypto.aesGcmEncrypt(key, shortNonce, "", "", empty.toSlice(), tag) as sizeError
    Swag.require(sizeError.value() is Errors.BadParameterError)
}

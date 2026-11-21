#global if #command == Swag.CompilerCommand.Test
#global private

func aesHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((aesHexDigit(text[index]) << 4) | aesHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

func assertAesVector(keyText, expectedText: string)
{
    let key       = aesHexBytes(keyText)
    let plaintext = aesHexBytes("00112233445566778899aabbccddeeff")
    let expected  = aesHexBytes(expectedText)
    var ciphertext: [Crypto.AesBlockSize] u8
    var decrypted:  [Crypto.AesBlockSize] u8
    var aes       = expect Crypto.Aes.create(key.toSlice())
    expect aes.encryptBlock(plaintext.toSlice(), ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected.toSlice()))
    expect aes.decryptBlock(ciphertext, decrypted)
    Swag.require(Crypto.constantTimeEqual(decrypted, plaintext.toSlice()))
}

#test
{
    // FIPS 197 test block for AES-128, AES-192, and AES-256.
    assertAesVector("000102030405060708090a0b0c0d0e0f", "69c4e0d86a7b0430d8cdb78070b4c55a")
    assertAesVector("000102030405060708090a0b0c0d0e0f1011121314151617", "dda97ca4864cdfe06eaf70a0ec0d7191")
    assertAesVector("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", "8ea2b7ca516745bfeafc49904b496089")
}

#test
{
    var invalidKey: [17] u8
    var keyError:   Swag.Error
    discard catch Crypto.Aes.create(invalidKey) as keyError
    Swag.require(keyError.value() is Errors.BadParameterError)

    var aes:    Crypto.Aes
    var block:  [16] u8
    var output: [16] u8
    var uninitializedError: Swag.Error
    discard catch aes.encryptBlock(block, output) as uninitializedError
    Swag.require(uninitializedError.value() is Errors.BadParameterError)

    var key: [16] u8
    expect aes.reset(key)
    var shortBlock: [15] u8
    var inputError: Swag.Error
    discard catch aes.encryptBlock(shortBlock, output) as inputError
    Swag.require(inputError.value() is Errors.BadParameterError)
}

#test
{
    let key       = aesHexBytes("000102030405060708090a0b0c0d0e0f")
    let plaintext = aesHexBytes("00112233445566778899aabbccddeeff")
    let expected  = aesHexBytes("69c4e0d86a7b0430d8cdb78070b4c55a")
    var aes       = expect Crypto.Aes.create(key.toSlice())
    var inPlace: [16] u8
    Swag.memcpy(&inPlace[0], &plaintext[0], inPlace.count)
    expect aes.encryptBlock(inPlace, inPlace)
    Swag.require(Crypto.constantTimeEqual(inPlace, expected.toSlice()))
    expect aes.decryptBlock(inPlace, inPlace)
    Swag.require(Crypto.constantTimeEqual(inPlace, plaintext.toSlice()))
    aes.clear()
}

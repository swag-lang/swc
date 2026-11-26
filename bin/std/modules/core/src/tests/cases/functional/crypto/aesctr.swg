#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func aesCtrHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func aesCtrHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((aesCtrHexDigit(text[index]) << 4) | aesCtrHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#test
{
    let key       = aesCtrHexBytes("2b7e151628aed2a6abf7158809cf4f3c")
    let iv        = aesCtrHexBytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    let plaintext = aesCtrHexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    let expected  = aesCtrHexBytes("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee")
    var ciphertext: [64] u8
    expect Crypto.aesCtrCrypt(key.toSlice(), iv.toSlice(), plaintext.toSlice(), ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected.toSlice()))

    expect Crypto.aesCtrCrypt(key.toSlice(), iv.toSlice(), ciphertext, ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, plaintext.toSlice()))
}

#test
{
    let key       = aesCtrHexBytes("8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b")
    let iv        = aesCtrHexBytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    let plaintext = aesCtrHexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    let expected  = aesCtrHexBytes("1abc932417521ca24f2b0459fe7e6e0b090339ec0aa6faefd5ccc2c6f4ce8e941e36b26bd1ebc670d1bd1d665620abf74f78a7f6d29809585a97daec58c6b050")
    var ciphertext: [64] u8
    expect Crypto.aesCtrCrypt(key.toSlice(), iv.toSlice(), plaintext.toSlice(), ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected.toSlice()))
}

#test
{
    let key       = aesCtrHexBytes("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
    let iv        = aesCtrHexBytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    let plaintext = aesCtrHexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    let expected  = aesCtrHexBytes("601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c52b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6")
    var ciphertext: [64] u8
    expect Crypto.aesCtrCrypt(key.toSlice(), iv.toSlice(), plaintext.toSlice(), ciphertext)
    Swag.require(Crypto.constantTimeEqual(ciphertext, expected.toSlice()))
}

#test
{
    var key:       [16] u8
    var counter:   [Crypto.AesCtrCounterSize] u8
    var plaintext: Array'u8
    plaintext.resize(65 * 1024 + 19)
    for index in plaintext.count do
        plaintext[index] = cast(u8, (index * 29 + 7) & 0xFF)
    var ciphertext: Array'u8
    ciphertext.resize(plaintext.count)
    Swag.setWorkerCount(4)
    expect Crypto.aesCtrCrypt(key, counter, plaintext.toSlice(), ciphertext.toSlice())
    var decrypted: Array'u8
    decrypted.resize(plaintext.count)
    expect Crypto.aesCtrCrypt(key, counter, ciphertext.toSlice(), decrypted.toSlice())
    Swag.require(Crypto.constantTimeEqual(plaintext.toSlice(), decrypted.toSlice()))
}

#test
{
    var key:     [16] u8
    var counter: [Crypto.AesCtrCounterSize] u8
    Memory.set(counter.buffer, 0xFF'u8, counter.count)
    var input:  [17] u8
    var output: [17] u8
    Memory.set(output.buffer, 0xA5'u8, output.count)
    var error: Swag.Error
    discard catch Crypto.aesCtrCrypt(key, counter, input, output) as error
    Swag.require(error.value() is Errors.BadParameterError)
    for value in output do
        Swag.require(value == 0xA5)
}

#test
{
    // OpenSSL AES-256-CTR across a carry into the high 64 bits, with an unaligned tail.
    let key        = aesCtrHexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let counter    = aesCtrHexBytes("c0c1c2c3c4c5c6c7fffffffffffffffe")
    let ciphertext = aesCtrHexBytes("f11deed95baa9faad6acb5a54a4339506299088f48335bde7ee00a45bd165fcaddc39226a2145f86b71bfcd0dc2c0ecf3b65dbcf1f8b25a90f7c607e35f7ea5368ca7d5652336a3c75d0bd36dcb9b5c6b973c0fbdaaba896dadfdb6bcc6303af4b")
    var buffer: [99] u8
    let data       = buffer[1 until 98]
    for index in data.count do
        data[index] = cast(u8, (index * 29 + 7) & 0xFF)
    let plaintext = buffer

    expect Crypto.aesCtrCrypt(key.toSlice(), counter.toSlice(), data, data)
    Swag.require(Crypto.constantTimeEqual(data, ciphertext.toSlice()))
    Swag.require(buffer[0] == 0 and buffer[98] == 0)

    expect Crypto.aesCtrCrypt(key.toSlice(), counter.toSlice(), data, data)
    Swag.require(Crypto.constantTimeEqual(buffer, plaintext))
}

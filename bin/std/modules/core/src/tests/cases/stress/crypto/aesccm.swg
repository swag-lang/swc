#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.TestTag("stress")]
#test
{
    // Exercise AES-CCM's parallel CTR path over a large partial-final-block record.
    var key:       [16] u8
    var nonce:     [7] u8
    var plaintext: Array'u8
    plaintext.resize(65 * 1024 + 19)
    for index in plaintext.count do
        plaintext[index] = cast(u8, index * 17 + 11)
    var ciphertext: Array'u8
    ciphertext.resize(plaintext.count)
    var tag: [Crypto.AesCcmTagMaxSize] u8
    Swag.setWorkerCount(4)
    expect Crypto.aesCcmEncrypt(key, nonce, "parallel-test-aad", plaintext.toSlice(), ciphertext.toSlice(), tag)
    var decrypted: Array'u8
    decrypted.resize(plaintext.count)
    expect Crypto.aesCcmDecrypt(key, nonce, "parallel-test-aad", ciphertext.toSlice(), tag, decrypted.toSlice())
    Swag.require(Crypto.constantTimeEqual(plaintext.toSlice(), decrypted.toSlice()))
}

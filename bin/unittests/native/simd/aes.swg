alias AesState = #simd [16] u8

#test
{
    if not Swag.hasCpuFeature(.Aes) do
        return

    let zero          = Swag.vecSplat(0'u8)
    let substitution  = Swag.vecSplat(0x63'u8)
    let roundKey      = Swag.vecSplat(0x31'u8)
    let encrypted     = Swag.vecAesEncryptRound(zero, roundKey)
    let encryptedLast = Swag.vecAesEncryptLastRound(zero, roundKey)
    let decrypted     = Swag.vecAesDecryptRound(substitution, roundKey)
    let decryptedLast = Swag.vecAesDecryptLastRound(substitution, roundKey)

    let mixed    = cast(AesState, [0x8E, 0x4D, 0xA1, 0xBC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    let restored = Swag.vecAesInverseMixColumns(mixed)
    let expected: [16] u8 = [0xDB, 0x13, 0x53, 0x45, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for index in expected.count
    {
        Swag.require(encrypted[index] == 0x52)
        Swag.require(encryptedLast[index] == 0x52)
        Swag.require(decrypted[index] == 0x31)
        Swag.require(decryptedLast[index] == 0x31)
        Swag.require(restored[index] == expected[index])
    }
}

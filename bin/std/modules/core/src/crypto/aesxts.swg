#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES-XTS data-unit tweak size in bytes.
public const AesXtsTweakSize = 16

private func aesXtsMultiplyTweak(tweak: *[AesXtsTweakSize] u8)
{
    var carry = 0'u8
    for index in AesXtsTweakSize
    {
        let next = tweak[][index] >> 7
        tweak[][index] = cast(u8, (tweak[][index] << 1) | carry)
        carry = next
    }

    tweak[][0] ^= 0x87'u8 & cast(u8, 0'u8 - carry)
}

#[Swag.Inline]
private func aesXtsMultiplyTweak(tweak: U8x16)->U8x16
{
    const Zero       = cast(U64x2, [0'u64, 0])
    const Polynomial = cast(U64x2, [0x87'u64, 0])
    const HighLanes  = cast(U64x2, [1'u64, 1])
    let value = cast #bit (U64x2, tweak)
    let carry = value >> 63
    let mask  = Zero - permute(carry, HighLanes)
    return cast #bit (U8x16, (value << 1) ^ align(Zero, carry, 8) ^ (mask & Polynomial))
}

#[Swag.Inline]
private func(Decrypt: bool) aesXtsCryptBlockHardware(aes: *Aes, tweak, input: U8x16)->U8x16
{
    #static if Decrypt do
        return aes[].decryptBlockHardware(input ^ tweak) ^ tweak
    else do
        return aes[].encryptBlockHardware(input ^ tweak) ^ tweak
}

private func(Decrypt: bool) aesXtsCryptBlocksHardware(aes: *Aes, initialTweak: U8x16, input: const [*] u8, output: [*] u8, blockCount: u64)->U8x16
{
    var tweak  = initialTweak
    var offset = 0'u64
    while offset + 4 <= blockCount
    {
        let second = aesXtsMultiplyTweak(tweak)
        let third  = aesXtsMultiplyTweak(second)
        let fourth = aesXtsMultiplyTweak(third)
        let bytes  = offset * AesBlockSize
        aes[].xorFourHardware'(true, Decrypt)(tweak, second, third, fourth, input + bytes, output + bytes)
        tweak   = aesXtsMultiplyTweak(fourth)
        offset += 4
    }

    while offset < blockCount
    {
        let bytes = offset * AesBlockSize
        store(output + bytes, aesXtsCryptBlockHardware'Decrypt(aes, tweak, load(input + bytes)))
        tweak   = aesXtsMultiplyTweak(tweak)
        offset += 1
    }

    return tweak
}

private func aesXtsCryptBlock(aes: *Aes, tweak: [AesXtsTweakSize] u8, input: *[AesXtsTweakSize] u8, output: *[AesXtsTweakSize] u8, decrypt: bool) fail
{
    if aes[].usesHardwareRounds()
    {
        let data = load(&input[][0])
        let whitening = load(&tweak[0])
        let result = decrypt ? aesXtsCryptBlockHardware'true(aes, whitening, data) : aesXtsCryptBlockHardware'false(aes, whitening, data)
        store(&output[][0], result)
        return
    }

    var block: [AesXtsTweakSize] u8
    for index in AesXtsTweakSize do
        block[index] = input[][index] ^ tweak[index]
    if decrypt
    {
        try aes[].decryptBlock(block, output[])
    }
    else
    {
        try aes[].encryptBlock(block, output[])
    }

    for index in AesXtsTweakSize do
        output[][index] ^= tweak[index]
    Crypto.secureClear(block)
}

// Encrypts or decrypts one XTS-AES data unit with a 32 or 64-byte combined key.
//
// `key` contains two equal AES keys, first the data key and then the tweak key. `dataUnitNumber`
// is the 16-byte tweak input. Data units contain 1 to 2^20 AES blocks; a partial final block is
// handled with ciphertext stealing. Input and output lengths must match; exact in-place operation
// and disjoint slices are supported, while partial overlap is unsupported. XTS provides no
// authentication and is intended for storage sectors, not general message encryption.
func aesXtsCrypt(key, dataUnitNumber, input: const [..] u8, output: [..] u8, decrypt: bool) fail
{
    if (key.count != 32 and key.count != 64) or
       dataUnitNumber.count != AesXtsTweakSize or
       input.count < AesBlockSize or
       output.count != input.count do
        fail Errors.BadParameterError{"AES-XTS needs a 32 or 64-byte key, a 16-byte data unit number, and matching data of at least 16 bytes"}
    if input.count > (1'u64 << 24) do
        fail Errors.BadParameterError{"AES-XTS data units cannot exceed 2^20 AES blocks"}

    let keySize = key.count / 2
    var dataAes = try Aes.create(key[0 until keySize])
    defer dataAes.clear()
    var tweakAes = try Aes.create(key[keySize until key.count])
    defer tweakAes.clear()

    var tweak: [AesXtsTweakSize] u8
    try tweakAes.encryptBlock(dataUnitNumber, tweak)
    let fullBlocks     = input.count / AesBlockSize
    let remainder      = input.count % AesBlockSize
    let ordinaryBlocks = fullBlocks - cast(u64, remainder != 0)
    if dataAes.usesHardwareRounds()
    {
        let initial = load(&tweak[0])
        let next = decrypt ? aesXtsCryptBlocksHardware'true(&dataAes, initial, input.buffer, output.buffer, ordinaryBlocks) :
                            aesXtsCryptBlocksHardware'false(&dataAes, initial, input.buffer, output.buffer, ordinaryBlocks)
        store(&tweak[0], next)
    }
    else
    {
        var offset = 0'u64
        while offset < ordinaryBlocks
        {
            let byteOffset = offset * AesBlockSize
            var source: [AesXtsTweakSize] u8
            var result: [AesXtsTweakSize] u8
            Swag.memcpy(&source[0], input.buffer + byteOffset, AesXtsTweakSize)
            try aesXtsCryptBlock(&dataAes, tweak, &source, &result, decrypt)
            Swag.memcpy(output.buffer + byteOffset, &result[0], AesXtsTweakSize)
            aesXtsMultiplyTweak(&tweak)
            Crypto.secureClear(source)
            Crypto.secureClear(result)
            offset += 1
        }
    }

    if remainder
    {
        let lastFullOffset = ordinaryBlocks * AesBlockSize
        let partialOffset  = lastFullOffset + AesBlockSize
        var sourceFull:    [AesXtsTweakSize] u8
        var sourcePartial: [AesXtsTweakSize] u8
        var intermediate:  [AesXtsTweakSize] u8
        var resultFull:    [AesXtsTweakSize] u8
        var nextTweak      = tweak
        Swag.memcpy(&sourceFull[0], input.buffer + lastFullOffset, AesXtsTweakSize)
        Swag.memcpy(&sourcePartial[0], input.buffer + partialOffset, remainder)
        aesXtsMultiplyTweak(&nextTweak)

        if decrypt
        {
            try aesXtsCryptBlock(&dataAes, nextTweak, &sourceFull, &intermediate, true)
            var stolen: [AesXtsTweakSize] u8
            for index in remainder do
                stolen[index] = sourcePartial[index]
            for index in remainder until AesXtsTweakSize do
                stolen[index] = intermediate[index]
            try aesXtsCryptBlock(&dataAes, tweak, &stolen, &resultFull, true)
            Swag.memcpy(output.buffer + lastFullOffset, &resultFull[0], AesXtsTweakSize)
            Swag.memcpy(output.buffer + partialOffset, &intermediate[0], remainder)
            Crypto.secureClear(stolen)
        }
        else
        {
            try aesXtsCryptBlock(&dataAes, tweak, &sourceFull, &intermediate, false)
            var stolen: [AesXtsTweakSize] u8
            for index in remainder do
                stolen[index] = sourcePartial[index]
            for index in remainder until AesXtsTweakSize do
                stolen[index] = intermediate[index]
            try aesXtsCryptBlock(&dataAes, nextTweak, &stolen, &resultFull, false)
            Swag.memcpy(output.buffer + lastFullOffset, &resultFull[0], AesXtsTweakSize)
            Swag.memcpy(output.buffer + partialOffset, &intermediate[0], remainder)
            Crypto.secureClear(stolen)
        }

        Crypto.secureClear(sourceFull)
        Crypto.secureClear(sourcePartial)
        Crypto.secureClear(intermediate)
        Crypto.secureClear(resultFull)
        Crypto.secureClear(nextTweak)
    }

    Crypto.secureClear(tweak)
}

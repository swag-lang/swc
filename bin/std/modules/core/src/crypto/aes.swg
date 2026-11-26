#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES block size in bytes.
public const AesBlockSize = 16

// Maximum AES key size in bytes.
public const AesMaxKeySize = 32

// Performs AES-128, AES-192, or AES-256 block operations with a key schedule that is cleared on drop.
//
// The software substitution avoids secret-indexed lookup tables and has a fixed operation path.
// AES supplies no mode, padding, or message authentication; use a separately reviewed construction for complete messages.
#[Swag.NoCopy, Swag.Opaque]
public struct Aes
{
    roundKeys:   [60] u32
    rounds:      u32
    ready:       bool
    useHardware: bool
}

#[Swag.Inline]
private func aesRotateByte(value: u8, bits: u8)->u8
{
    return cast(u8, (value << bits) | (value >> (8 - bits)))
}

#[Swag.Inline]
private func aesDouble(value: u8)->u8
{
    let highMask = cast(u8, 0'u8 - (value >> 7))
    return cast(u8, (value << 1) ^ (0x1B'u8 & highMask))
}

#[Swag.Inline]
private func aesMultiply(left, right: u8)->u8
{
    var a         = left
    var b         = right
    var result    = 0'u8
    var iteration = 0'u32
    while iteration < 8
    {
        let selected = cast(u8, 0'u8 - (b & 1))
        result    ^= a & selected
        a         = aesDouble(a)
        b         >>= 1
        iteration += 1
    }

    return result
}

private func aesInverse(value: u8)->u8
{
    let square2   = aesMultiply(value, value)
    let square4   = aesMultiply(square2, square2)
    let square8   = aesMultiply(square4, square4)
    let square16  = aesMultiply(square8, square8)
    let square32  = aesMultiply(square16, square16)
    let square64  = aesMultiply(square32, square32)
    let square128 = aesMultiply(square64, square64)
    var result    = aesMultiply(square128, square64)
    result = aesMultiply(result, square32)
    result = aesMultiply(result, square16)
    result = aesMultiply(result, square8)
    result = aesMultiply(result, square4)
    result = aesMultiply(result, square2)
    return result
}

#[Swag.Inline]
private func aesSubstitute(value: u8)->u8
{
    let inverse = aesInverse(value)
    return inverse ^ aesRotateByte(inverse, 1) ^ aesRotateByte(inverse, 2) ^
           aesRotateByte(inverse, 3) ^ aesRotateByte(inverse, 4) ^ 0x63
}

#[Swag.Inline]
private func aesInverseSubstitute(value: u8)->u8
{
    let affine = aesRotateByte(value, 1) ^ aesRotateByte(value, 3) ^ aesRotateByte(value, 6) ^ 0x05
    return aesInverse(affine)
}

#[Swag.Inline]
private func aesSubWord(value: u32, useHardware: bool)->u32
{
    if useHardware
    {
        // With four identical columns, ShiftRows leaves every row unchanged.
        const Zero = Swag.vecSplat(0'u8)
        let columns = cast #bit (U8x16, splat(value))
        return cast #bit (U32x4, Swag.vecAesEncryptLastRound(columns, Zero))[0]
    }

    return cast(u32, aesSubstitute(Math.byteAt(value, 0))) |
           (cast(u32, aesSubstitute(Math.byteAt(value, 1))) << 8) |
           (cast(u32, aesSubstitute(Math.byteAt(value, 2))) << 16) |
           (cast(u32, aesSubstitute(Math.byteAt(value, 3))) << 24)
}

public impl Aes
{
    // Creates an AES cipher from a 16, 24, or 32-byte key.
    func create(key: const [..] u8)->Aes fail
    {
        var result: #returntype
        try result.reset(key)
        return result
    }

    // Replaces the key schedule with AES-128, AES-192, or AES-256 key material.
    //
    // Fails with [[Core.Errors.BadParameterError]] when the key length is not 16, 24, or 32 bytes.
    mtd reset(key: const [..] u8) fail
    {
        if key.count != 16 and key.count != 24 and key.count != 32 do
            fail Errors.BadParameterError{"AES key must contain 16, 24, or 32 bytes"}

        let keyWords    = key.count / 4
        let rounds      = cast(u32, keyWords + 6)
        let useHardware = Swag.hasCpuFeature(.Aes)
        var expanded: [60] u32
        Swag.memcpy(&expanded[0], key.buffer, key.count)
        #static if BIG_ENDIAN
        {
            for index in keyWords do
                expanded[index] = Swag.byteSwap(expanded[index])
        }

        let wordCount     = 4 * (rounds + 1)
        var roundConstant = 1'u8
        var column        = 0'u64
        var previousWord  = expanded[keyWords - 1]
        for index in keyWords until wordCount
        {
            var temp = previousWord
            if column == 0
            {
                temp = aesSubWord(Swag.ror(temp, 8'u8), useHardware) ^ roundConstant
                roundConstant = aesDouble(roundConstant)
            }
            elif keyWords > 6 and column == 4
            {
                temp = aesSubWord(temp, useHardware)
            }

            previousWord   = expanded[index - keyWords] ^ temp
            expanded[index] = previousWord
            column += 1
            if column == keyWords do
                column = 0
        }

        .clear()
        #static if BIG_ENDIAN
        {
            for index in wordCount do
                expanded[index] = Swag.byteSwap(expanded[index])
        }

        Swag.memcpy(&.roundKeys[0], &expanded[0], wordCount * #sizeof(u32))
        .rounds      = rounds
        .ready       = true
        .useHardware = useHardware
        Crypto.secureClear(expanded)
    }

    // Encrypts exactly one 16-byte block. Source and destination may be the same range.
    //
    // Fails with [[Core.Errors.BadParameterError]] when no key is initialized or either slice is not 16 bytes.
    mtd encryptBlock(source: const [..] u8, destination: [..] u8) fail
    {
        try .validateBlockRanges(source, destination)
        if .useHardware
        {
            store(destination.buffer, .encryptBlockHardware(load(source.buffer)))
            return
        }

        var state: [AesBlockSize] u8
        Swag.memcpy(&state[0], source.buffer, AesBlockSize)
        .addRoundKey(&state, 0)

        for round in 1 until .rounds
        {
            for index in AesBlockSize do
                state[index] = aesSubstitute(state[index])
            .shiftRows(&state)
            .mixColumns(&state)
            .addRoundKey(&state, round)
        }

        for index in AesBlockSize do
            state[index] = aesSubstitute(state[index])
        .shiftRows(&state)
        .addRoundKey(&state, .rounds)
        Swag.memcpy(destination.buffer, &state[0], AesBlockSize)
        Crypto.secureClear(state)
    }

    // Decrypts exactly one 16-byte block. Source and destination may be the same range.
    //
    // Fails with [[Core.Errors.BadParameterError]] when no key is initialized or either slice is not 16 bytes.
    mtd decryptBlock(source: const [..] u8, destination: [..] u8) fail
    {
        try .validateBlockRanges(source, destination)
        if .useHardware
        {
            store(destination.buffer, .decryptBlockHardware(load(source.buffer)))
            return
        }

        var state: [AesBlockSize] u8
        Swag.memcpy(&state[0], source.buffer, AesBlockSize)
        .addRoundKey(&state, .rounds)

        for round in 1 until .rounds
        {
            .inverseShiftRows(&state)
            for index in AesBlockSize do
                state[index] = aesInverseSubstitute(state[index])
            .addRoundKey(&state, .rounds - round)
            .inverseMixColumns(&state)
        }

        .inverseShiftRows(&state)
        for index in AesBlockSize do
            state[index] = aesInverseSubstitute(state[index])
        .addRoundKey(&state, 0)
        Swag.memcpy(destination.buffer, &state[0], AesBlockSize)
        Crypto.secureClear(state)
    }

    // Clears the expanded key schedule.
    mtd clear()
    {
        Crypto.secureClear(.roundKeys)
        .rounds      = 0
        .ready       = false
        .useHardware = false
    }

    private mtd validateBlockRanges(source: const [..] u8, destination: [..] u8) fail
    {
        if not .ready do
            fail Errors.BadParameterError{"AES needs an initialized key"}
        if source.count != AesBlockSize or destination.count != AesBlockSize do
            fail Errors.BadParameterError{"AES block operations need exactly 16 input and output bytes"}
    }

    #[Swag.Inline]
    private mtd roundKey(round: u32)->U8x16
    {
        return load(cast(const [*] u8, &.roundKeys[round * 4]))
    }

    #[Swag.Inline]
    internal mtd encryptBlockHardware(value: U8x16)->U8x16
    {
        var state = value ^ .roundKey(0)
        for round in 1 until .rounds do
            state = Swag.vecAesEncryptRound(state, .roundKey(round))
        return Swag.vecAesEncryptLastRound(state, .roundKey(.rounds))
    }

    #[Swag.Inline]
    internal mtd usesHardwareRounds() => .useHardware

    // The caller provides four complete blocks and has selected the hardware rounds.
    #[Swag.Inline]
    internal mtd xorFourHardware(first, second, third, fourth: U8x16, source: const [*] u8, destination: [*] u8)
    {
        let initial     = .roundKey(0)
        var firstState  = first ^ initial
        var secondState = second ^ initial
        var thirdState  = third ^ initial
        var fourthState = fourth ^ initial
        for round in 1 until .rounds
        {
            let key = .roundKey(round)
            firstState  = Swag.vecAesEncryptRound(firstState, key)
            secondState = Swag.vecAesEncryptRound(secondState, key)
            thirdState  = Swag.vecAesEncryptRound(thirdState, key)
            fourthState = Swag.vecAesEncryptRound(fourthState, key)
        }

        let final = .roundKey(.rounds)
        store(destination, load(source) ^ Swag.vecAesEncryptLastRound(firstState, final))
        store(destination + AesBlockSize, load(source + AesBlockSize) ^ Swag.vecAesEncryptLastRound(secondState, final))
        store(destination + 2 * AesBlockSize, load(source + 2 * AesBlockSize) ^ Swag.vecAesEncryptLastRound(thirdState, final))
        store(destination + 3 * AesBlockSize, load(source + 3 * AesBlockSize) ^ Swag.vecAesEncryptLastRound(fourthState, final))
    }

    #[Swag.Inline]
    private mtd decryptBlockHardware(value: U8x16)->U8x16
    {
        var state = value ^ .roundKey(.rounds)
        for round in 1 until .rounds
        {
            let inverseRoundKey = Swag.vecAesInverseMixColumns(.roundKey(.rounds - round))
            state = Swag.vecAesDecryptRound(state, inverseRoundKey)
        }

        return Swag.vecAesDecryptLastRound(state, .roundKey(0))
    }

    private mtd addRoundKey(state: *[AesBlockSize] u8, round: u32)
    {
        store(&state[][0], load(&state[][0]) ^ .roundKey(round))
    }

    private mtd shiftRows(state: *[AesBlockSize] u8)
    {
        var shifted: [AesBlockSize] u8
        for column in 4
        {
            for row in 4 do
                shifted[column * 4 + row] = state[][((column + row) % 4) * 4 + row]
        }

        state[] = shifted
    }

    private mtd inverseShiftRows(state: *[AesBlockSize] u8)
    {
        var shifted: [AesBlockSize] u8
        for column in 4
        {
            for row in 4 do
                shifted[column * 4 + row] = state[][((column + 4 - row) % 4) * 4 + row]
        }

        state[] = shifted
    }

    private mtd mixColumns(state: *[AesBlockSize] u8)
    {
        for column in 4
        {
            let offset = column * 4
            let a      = state[][offset]
            let b      = state[][offset + 1]
            let c      = state[][offset + 2]
            let d      = state[][offset + 3]
            let total  = a ^ b ^ c ^ d
            state[][offset]     = a ^ total ^ aesDouble(a ^ b)
            state[][offset + 1] = b ^ total ^ aesDouble(b ^ c)
            state[][offset + 2] = c ^ total ^ aesDouble(c ^ d)
            state[][offset + 3] = d ^ total ^ aesDouble(d ^ a)
        }
    }

    private mtd inverseMixColumns(state: *[AesBlockSize] u8)
    {
        for column in 4
        {
            let offset = column * 4
            let a      = state[][offset]
            let b      = state[][offset + 1]
            let c      = state[][offset + 2]
            let d      = state[][offset + 3]
            state[][offset]     = aesMultiply(a, 14) ^ aesMultiply(b, 11) ^ aesMultiply(c, 13) ^ aesMultiply(d, 9)
            state[][offset + 1] = aesMultiply(a, 9) ^ aesMultiply(b, 14) ^ aesMultiply(c, 11) ^ aesMultiply(d, 13)
            state[][offset + 2] = aesMultiply(a, 13) ^ aesMultiply(b, 9) ^ aesMultiply(c, 14) ^ aesMultiply(d, 11)
            state[][offset + 3] = aesMultiply(a, 11) ^ aesMultiply(b, 13) ^ aesMultiply(c, 9) ^ aesMultiply(d, 14)
        }
    }

    // Clears the expanded key schedule when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}

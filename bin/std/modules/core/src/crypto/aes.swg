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
// Software substitution follows a fixed operation path and avoids secret-dependent memory accesses.
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
private func aesDouble(value: u8)->u8
{
    let highMask = cast(u8, 0'u8 - (value >> 7))
    return cast(u8, (value << 1) ^ (0x1B'u8 & highMask))
}

#[Swag.Inline]
private func aesDouble(value: U8x16)->U8x16
{
    const Zero = Swag.vecSplat(0'u8)
    let highMask = Zero - (value >> 7)
    return (value + value) ^ (highMask & 0x1B'u8)
}

#[Swag.Inline]
private func aesNibbleMap(value, lowTable, highTable: U8x16)->U8x16
{
    return shuffle(lowTable, value & 0x0F'u8) ^ shuffle(highTable, value >> 4)
}

#[Swag.Inline]
private func aesGf16Multiply(left, right: U8x16)->U8x16
{
    const Zero   = Swag.vecSplat(0'u8)
    const Logs   = cast(U8x16, [0x00, 0x00, 0x01, 0x04, 0x02, 0x08, 0x05, 0x0A, 0x03, 0x0E, 0x09, 0x07, 0x06, 0x0D, 0x0B, 0x0C])
    const Powers = cast(U8x16, [0x01, 0x02, 0x04, 0x08, 0x03, 0x06, 0x0C, 0x0B, 0x05, 0x0A, 0x07, 0x0E, 0x0F, 0x0D, 0x09, 0x01])
    let sum = shuffle(Logs, left) + shuffle(Logs, right)

    // Since 16 is congruent to 1 modulo 15, fold the carry back into the low nibble.
    let product = shuffle(Powers, (sum & 0x0F'u8) + (sum >> 4))
    return product & (left != Zero) & (right != Zero)
}

#[Swag.Inline]
private func aesInvertTower(value: U8x16)->U8x16
{
    const Reciprocal   = cast(U8x16, [0x00, 0x01, 0x09, 0x0E, 0x0D, 0x0B, 0x07, 0x06, 0x0F, 0x02, 0x0C, 0x05, 0x0A, 0x04, 0x03, 0x08])
    const ScaledSquare = cast(U8x16, [0x00, 0x0B, 0x0A, 0x01, 0x0E, 0x05, 0x04, 0x0F, 0x0D, 0x06, 0x07, 0x0C, 0x03, 0x08, 0x09, 0x02])

    // In the tower basis a*z + b, z^2 + z is the subfield element 0x0B.
    // The norm is b*(a+b) + 0x0B*a^2. The conjugate has coefficients a and a+b.
    let a           = value >> 4
    let b           = value & 0x0F'u8
    let complement  = a ^ b
    let norm        = aesGf16Multiply(b, complement) ^ shuffle(ScaledSquare, a)
    let inverseNorm = shuffle(Reciprocal, norm)
    return (aesGf16Multiply(a, inverseNorm) << 4) | aesGf16Multiply(complement, inverseNorm)
}

#[Swag.Inline]
private func aesSubstitute(value: U8x16)->U8x16
{
    // The subfield uses t^4 + t + 1. Its generator is 0x5C in AES coordinates and z is 0x12.
    // Each byte maps through register shuffles. No secret selects a memory address.
    const EncodeLow        = cast(U8x16, [0x00, 0x01, 0x2B, 0x2A, 0x43, 0x42, 0x68, 0x69, 0x49, 0x48, 0x62, 0x63, 0x0A, 0x0B, 0x21, 0x20])
    const EncodeHigh       = cast(U8x16, [0x00, 0x3B, 0xD6, 0xED, 0x33, 0x08, 0xE5, 0xDE, 0xE1, 0xDA, 0x37, 0x0C, 0xD2, 0xE9, 0x04, 0x3F])
    const DecodeAffineLow  = cast(U8x16, [0x00, 0x1F, 0xB2, 0xAD, 0xAB, 0xB4, 0x19, 0x06, 0x36, 0x29, 0x84, 0x9B, 0x9D, 0x82, 0x2F, 0x30])
    const DecodeAffineHigh = cast(U8x16, [0x00, 0xCF, 0xA5, 0x6A, 0xD1, 0x1E, 0x74, 0xBB, 0xE4, 0x2B, 0x41, 0x8E, 0x35, 0xFA, 0x90, 0x5F])
    let tower = aesNibbleMap(value, EncodeLow, EncodeHigh)
    return aesNibbleMap(aesInvertTower(tower), DecodeAffineLow, DecodeAffineHigh) ^ 0x63'u8
}

#[Swag.Inline]
private func aesInverseSubstitute(value: U8x16)->U8x16
{
    const EncodeInverseAffineLow  = cast(U8x16, [0x00, 0x51, 0x99, 0xC8, 0x9E, 0xCF, 0x07, 0x56, 0x23, 0x72, 0xBA, 0xEB, 0xBD, 0xEC, 0x24, 0x75])
    const EncodeInverseAffineHigh = cast(U8x16, [0x00, 0x74, 0x7B, 0x0F, 0xF1, 0x85, 0x8A, 0xFE, 0x94, 0xE0, 0xEF, 0x9B, 0x65, 0x11, 0x1E, 0x6A])
    const DecodeLow               = cast(U8x16, [0x00, 0x01, 0x5C, 0x5D, 0xE0, 0xE1, 0xBC, 0xBD, 0x50, 0x51, 0x0C, 0x0D, 0xB0, 0xB1, 0xEC, 0xED])
    const DecodeHigh              = cast(U8x16, [0x00, 0x12, 0x0F, 0x1D, 0x59, 0x4B, 0x56, 0x44, 0xD7, 0xC5, 0xD8, 0xCA, 0x8E, 0x9C, 0x81, 0x93])

    // The inverse affine constant 0x05 maps to 0x42 in the tower basis.
    let tower = aesNibbleMap(value, EncodeInverseAffineLow, EncodeInverseAffineHigh) ^ 0x42'u8
    return aesNibbleMap(aesInvertTower(tower), DecodeLow, DecodeHigh)
}

#[Swag.Inline]
private func aesSubWord(value: u32, useHardware: bool)->u32
{
    // With four identical columns, ShiftRows leaves every row unchanged.
    const Zero = Swag.vecSplat(0'u8)
    let columns     = cast #bit (U8x16, splat(value))
    let substituted = useHardware ? Swag.vecAesEncryptLastRound(columns, Zero) : aesSubstitute(columns)
    return cast #bit (U32x4, substituted)[0]
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
        if useHardware and keyWords != 6
        {
            .expandHardwareKey(key)
            .rounds      = rounds
            .ready       = true
            .useHardware = true
            return
        }

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

        const ShiftRows = cast(U8x16, [0'u8, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11])
        var state: [1] U8x16
        state[0] = load(source.buffer) ^ .roundKey(0)
        for round in 1 until .rounds
        {
            let shifted = shuffle(aesSubstitute(state[0]), ShiftRows)
            state[0] = .mixColumns(shifted) ^ .roundKey(round)
        }

        store(destination.buffer, shuffle(aesSubstitute(state[0]), ShiftRows) ^ .roundKey(.rounds))
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

        const ShiftRows = cast(U8x16, [0'u8, 13, 10, 7, 4, 1, 14, 11, 8, 5, 2, 15, 12, 9, 6, 3])
        var state: [1] U8x16
        state[0] = load(source.buffer) ^ .roundKey(.rounds)
        for round in 1 until .rounds
        {
            let substituted = aesInverseSubstitute(shuffle(state[0], ShiftRows))
            state[0] = .inverseMixColumns(substituted ^ .roundKey(.rounds - round))
        }

        store(destination.buffer, aesInverseSubstitute(shuffle(state[0], ShiftRows)) ^ .roundKey(0))
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

    private mtd expandHardwareKey(key: const [..] u8)
    {
        const RoundConstants: [10] u32 = [1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]
        const Zero        = Swag.vecSplat(0'u8)
        const RotatedWord = cast(U8x16, [13'u8, 14, 15, 12, 13, 14, 15, 12, 13, 14, 15, 12, 13, 14, 15, 12])
        const LastWord    = cast(U8x16, [12'u8, 13, 14, 15, 12, 13, 14, 15, 12, 13, 14, 15, 12, 13, 14, 15])

        #[Swag.Inline]
        func nextKey(current, substituted: U8x16)->U8x16
        {
            let pairs = current ^ align(Zero, current, 12)
            return pairs ^ align(Zero, pairs, 8) ^ substituted
        }

        var left = load(key.buffer)
        let output = cast([*] u8, &.roundKeys[0])
        if key.count == 16
        {
            .clear()
            store(output, left)
            for round in 1 until 11
            {
                let roundConstant = cast #bit (U8x16, splat(RoundConstants[round - 1]))
                let substituted = Swag.vecAesEncryptLastRound(shuffle(left, RotatedWord), roundConstant)
                left = nextKey(left, substituted)
                store(output + round * AesBlockSize, left)
            }

            return
        }

        var right = load(key.buffer + AesBlockSize)
        .clear()
        store(output, left)
        store(output + AesBlockSize, right)
        for pair in 1 until 8
        {
            let round = pair * 2
            let roundConstant = cast #bit (U8x16, splat(RoundConstants[pair - 1]))
            let substituted = Swag.vecAesEncryptLastRound(shuffle(right, RotatedWord), roundConstant)
            left = nextKey(left, substituted)
            store(output + round * AesBlockSize, left)
            if pair == 7 do
                break

            right = nextKey(right, Swag.vecAesEncryptLastRound(shuffle(left, LastWord), Zero))
            store(output + (round + 1) * AesBlockSize, right)
        }
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

    #[Swag.Inline]
    private mtd mixColumns(state: U8x16)->U8x16
    {
        const Adjacent = cast(U8x16, [1'u8, 2, 3, 0, 5, 6, 7, 4, 9, 10, 11, 8, 13, 14, 15, 12])
        const Opposite = cast(U8x16, [2'u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
        let difference = state ^ shuffle(state, Adjacent)
        let sum        = difference ^ shuffle(difference, Opposite)
        return state ^ sum ^ aesDouble(difference)
    }

    #[Swag.Inline]
    private mtd inverseMixColumns(state: U8x16)->U8x16
    {
        const Opposite = cast(U8x16, [2'u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
        let correction = aesDouble(aesDouble(state ^ shuffle(state, Opposite)))
        return .mixColumns(state ^ correction)
    }

    // Clears the expanded key schedule when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}

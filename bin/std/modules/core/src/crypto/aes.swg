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

private const AesSoftwareShiftRows = cast(U8x16, [0'u8, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11])

#[Swag.Inline]
private func aesDouble(value: u8)->u8
{
    let highMask = cast(u8, 0'u8 - (value >> 7))
    return cast(u8, (value << 1) ^ (0x1B'u8 & highMask))
}

#[Swag.Inline]
private func aesNibbleMap(value, lowTable, highTable: U8x16)->U8x16
{
    return shuffle(lowTable, value & 0x0F'u8) ^ shuffle(highTable, value >> 4)
}

#[Swag.Inline]
private func aesTowerEncode(value: U8x16)->U8x16
{
    // The subfield uses t^4 + t + 1. Its generator is 0x5C and z is 0x12 in AES coordinates.
    const Low  = cast(U8x16, [0x00, 0x01, 0x2B, 0x2A, 0x43, 0x42, 0x68, 0x69, 0x49, 0x48, 0x62, 0x63, 0x0A, 0x0B, 0x21, 0x20])
    const High = cast(U8x16, [0x00, 0x3B, 0xD6, 0xED, 0x33, 0x08, 0xE5, 0xDE, 0xE1, 0xDA, 0x37, 0x0C, 0xD2, 0xE9, 0x04, 0x3F])
    return aesNibbleMap(value, Low, High)
}

#[Swag.Inline]
private func aesTowerDecode(value: U8x16)->U8x16
{
    const Low  = cast(U8x16, [0x00, 0x01, 0x5C, 0x5D, 0xE0, 0xE1, 0xBC, 0xBD, 0x50, 0x51, 0x0C, 0x0D, 0xB0, 0xB1, 0xEC, 0xED])
    const High = cast(U8x16, [0x00, 0x12, 0x0F, 0x1D, 0x59, 0x4B, 0x56, 0x44, 0xD7, 0xC5, 0xD8, 0xCA, 0x8E, 0x9C, 0x81, 0x93])
    return aesNibbleMap(value, Low, High)
}

#[Swag.Inline]
private func aesTowerDouble(value: U8x16)->U8x16
{
    const Low  = cast(U8x16, [0x00, 0x2B, 0x45, 0x6E, 0x8A, 0xA1, 0xCF, 0xE4, 0x37, 0x1C, 0x72, 0x59, 0xBD, 0x96, 0xF8, 0xD3])
    const High = cast(U8x16, [0x00, 0x95, 0x1A, 0x8F, 0x27, 0xB2, 0x3D, 0xA8, 0x4E, 0xDB, 0x54, 0xC1, 0x69, 0xFC, 0x73, 0xE6])
    return aesNibbleMap(value, Low, High)
}

#[Swag.Inline]
private func aesGf16PowerIndex(leftLog, rightLog: U8x16)->U8x16
{
    // Reduce exponents modulo 15 by folding the high nibble. Zero has log 0xC0,
    // and the high bit survives addition with any other log and the fold.
    let sum = leftLog + rightLog
    return sum + (sum >> 4)
}

#[Swag.Inline]
private func aesInvertTower(value: U8x16)->U8x16
{
    const Logs           = cast(U8x16, [0xC0, 0x00, 0x01, 0x04, 0x02, 0x08, 0x05, 0x0A, 0x03, 0x0E, 0x09, 0x07, 0x06, 0x0D, 0x0B, 0x0C])
    const Powers         = cast(U8x16, [0x01, 0x02, 0x04, 0x08, 0x03, 0x06, 0x0C, 0x0B, 0x05, 0x0A, 0x07, 0x0E, 0x0F, 0x0D, 0x09, 0x01])
    const HighPowers     = cast(U8x16, [0x10, 0x20, 0x40, 0x80, 0x30, 0x60, 0xC0, 0xB0, 0x50, 0xA0, 0x70, 0xE0, 0xF0, 0xD0, 0x90, 0x10])
    const ReciprocalLogs = cast(U8x16, [0xC0, 0x00, 0x0E, 0x0B, 0x0D, 0x07, 0x0A, 0x05, 0x0C, 0x01, 0x06, 0x08, 0x09, 0x02, 0x04, 0x03])
    const ScaledSquare   = cast(U8x16, [0x00, 0x0B, 0x0A, 0x01, 0x0E, 0x05, 0x04, 0x0F, 0x0D, 0x06, 0x07, 0x0C, 0x03, 0x08, 0x09, 0x02])

    // In the tower basis a*z + b, z^2 + z is the subfield element 0x0B.
    // The norm is b*(a+b) + 0x0B*a^2. The conjugate has coefficients a and a+b.
    let a             = value >> 4
    let b             = value & 0x0F'u8
    let complementLog = shuffle(Logs, a ^ b)
    let normProduct   = shuffle(Powers, aesGf16PowerIndex(shuffle(Logs, b), complementLog))
    let norm          = normProduct ^ shuffle(ScaledSquare, a)
    let inverseNormLog = shuffle(ReciprocalLogs, norm)
    let high          = shuffle(HighPowers, aesGf16PowerIndex(shuffle(Logs, a), inverseNormLog))
    let low           = shuffle(Powers, aesGf16PowerIndex(complementLog, inverseNormLog))
    return high | low
}

#[Swag.Inline]
private func aesSubstitute(value: U8x16)->U8x16
{
    const DecodeAffineLow  = cast(U8x16, [0x00, 0x1F, 0xB2, 0xAD, 0xAB, 0xB4, 0x19, 0x06, 0x36, 0x29, 0x84, 0x9B, 0x9D, 0x82, 0x2F, 0x30])
    const DecodeAffineHigh = cast(U8x16, [0x00, 0xCF, 0xA5, 0x6A, 0xD1, 0x1E, 0x74, 0xBB, 0xE4, 0x2B, 0x41, 0x8E, 0x35, 0xFA, 0x90, 0x5F])
    let tower = aesTowerEncode(value)
    return aesNibbleMap(aesInvertTower(tower), DecodeAffineLow, DecodeAffineHigh) ^ 0x63'u8
}

#[Swag.Inline]
private func aesTowerSubstitute(value: U8x16)->U8x16
{
    const Low  = cast(U8x16, [0xCF, 0xD4, 0xE8, 0xF3, 0x9B, 0x80, 0xBC, 0xA7, 0x4A, 0x51, 0x6D, 0x76, 0x1E, 0x05, 0x39, 0x22])
    const High = cast(U8x16, [0x00, 0xF2, 0x75, 0x87, 0xE8, 0x1A, 0x9D, 0x6F, 0x47, 0xB5, 0x32, 0xC0, 0xAF, 0x5D, 0xDA, 0x28])
    return aesNibbleMap(aesInvertTower(value), Low, High)
}

#[Swag.Inline]
private func aesTowerInverseSubstitute(value: U8x16)->U8x16
{
    const Low  = cast(U8x16, [0x42, 0x13, 0x7A, 0x2B, 0x5C, 0x0D, 0x64, 0x35, 0xC7, 0x96, 0xFF, 0xAE, 0xD9, 0x88, 0xE1, 0xB0])
    const High = cast(U8x16, [0x00, 0xED, 0x75, 0x98, 0xF7, 0x1A, 0x82, 0x6F, 0x47, 0xAA, 0x32, 0xDF, 0xB0, 0x5D, 0xC5, 0x28])
    return aesInvertTower(aesNibbleMap(value, Low, High))
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

        if useHardware
        {
            Swag.memcpy(&.roundKeys[0], &expanded[0], wordCount * #sizeof(u32))
        }
        else
        {
            // Software rounds stay in the tower basis, including AddRoundKey and MixColumns.
            let source = cast(const [*] u8, &expanded[0])
            let output = cast([*] u8, &.roundKeys[0])
            for round in rounds + 1
            {
                let offset = round * AesBlockSize
                store(output + offset, aesTowerEncode(load(source + offset)))
            }
        }
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

        var state: [1] U8x16
        state[0] = aesTowerEncode(load(source.buffer)) ^ .roundKey(0)
        for round in 1 until .rounds do
            state[0] = .encryptSoftwareRound(state[0], .roundKey(round))

        store(destination.buffer, aesTowerDecode(shuffle(aesTowerSubstitute(state[0]), AesSoftwareShiftRows) ^ .roundKey(.rounds)))
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
            store(destination.buffer, .decryptBlockHardware'false(load(source.buffer)))
            return
        }

        const ShiftRows = cast(U8x16, [0'u8, 13, 10, 7, 4, 1, 14, 11, 8, 5, 2, 15, 12, 9, 6, 3])
        var state: [1] U8x16
        state[0] = aesTowerEncode(load(source.buffer)) ^ .roundKey(.rounds)
        for round in 1 until .rounds
        {
            let substituted = aesTowerInverseSubstitute(shuffle(state[0], ShiftRows))
            state[0] = .inverseMixColumns(substituted ^ .roundKey(.rounds - round))
        }

        store(destination.buffer, aesTowerDecode(aesTowerInverseSubstitute(shuffle(state[0], ShiftRows)) ^ .roundKey(0)))
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
    internal mtd roundKey(round: u32)->U8x16
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
    internal mtd hardwareRoundCount() => .rounds

    #[Swag.Inline]
    internal mtd usesHardwareRounds() => .useHardware

    // Converts the intermediate hardware round keys for use by the decryption rounds.
    internal mtd prepareHardwareDecryption()
    {
        let bytes = cast([*] u8, &.roundKeys[0])
        for round in 1 until .rounds do
            store(bytes + round * AesBlockSize, Swag.vecAesInverseMixColumns(.roundKey(round)))
    }

    // The caller provides four complete blocks and has selected the hardware rounds.
    // Decryption uses a schedule prepared by prepareHardwareDecryption.
    #[Swag.Inline]
    internal mtd(Xts: bool, Decrypt: bool) xorFourHardware(first, second, third, fourth: U8x16, source: const [*] u8, destination: [*] u8)
    {
        #[Swag.Inline]
        func round(value, key: U8x16)->U8x16
        {
            #static if Decrypt do
                return Swag.vecAesDecryptRound(value, key)
            else do
                return Swag.vecAesEncryptRound(value, key)
        }

        #[Swag.Inline]
        func finalRound(value, key: U8x16)->U8x16
        {
            #static if Decrypt do
                return Swag.vecAesDecryptLastRound(value, key)
            else do
                return Swag.vecAesEncryptLastRound(value, key)
        }

        let initial     = .roundKey(Decrypt ? .rounds : 0)
        var firstState  = first ^ initial
        var secondState = second ^ initial
        var thirdState  = third ^ initial
        var fourthState = fourth ^ initial
        #static if Xts
        {
            firstState  ^= load(source)
            secondState ^= load(source + AesBlockSize)
            thirdState  ^= load(source + 2 * AesBlockSize)
            fourthState ^= load(source + 3 * AesBlockSize)
        }

        for index in 1 until .rounds
        {
            let key = .roundKey(Decrypt ? .rounds - index : index)
            firstState  = round(firstState, key)
            secondState = round(secondState, key)
            thirdState  = round(thirdState, key)
            fourthState = round(fourthState, key)
        }

        let final = .roundKey(Decrypt ? 0 : .rounds)
        #static if Xts
        {
            store(destination, finalRound(firstState, final) ^ first)
            store(destination + AesBlockSize, finalRound(secondState, final) ^ second)
            store(destination + 2 * AesBlockSize, finalRound(thirdState, final) ^ third)
            store(destination + 3 * AesBlockSize, finalRound(fourthState, final) ^ fourth)
        }
        else
        {
            store(destination, finalRound(firstState, final) ^ load(source))
            store(destination + AesBlockSize, finalRound(secondState, final) ^ load(source + AesBlockSize))
            store(destination + 2 * AesBlockSize, finalRound(thirdState, final) ^ load(source + 2 * AesBlockSize))
            store(destination + 3 * AesBlockSize, finalRound(fourthState, final) ^ load(source + 3 * AesBlockSize))
        }
    }

    // The caller provides a complete batch of independent counter blocks.
    #[Swag.Inline]
    internal mtd xorEightCountersHardware(first, second, third, fourth, fifth, sixth, seventh, eighth: U8x16, source: const [*] u8, destination: [*] u8)
    {
        let initial      = .roundKey(0)
        var firstState   = first ^ initial
        var secondState  = second ^ initial
        var thirdState   = third ^ initial
        var fourthState  = fourth ^ initial
        var fifthState   = fifth ^ initial
        var sixthState   = sixth ^ initial
        var seventhState = seventh ^ initial
        var eighthState  = eighth ^ initial

        for index in 1 until .rounds
        {
            let key = .roundKey(index)
            firstState    = Swag.vecAesEncryptRound(firstState, key)
            secondState   = Swag.vecAesEncryptRound(secondState, key)
            thirdState    = Swag.vecAesEncryptRound(thirdState, key)
            fourthState   = Swag.vecAesEncryptRound(fourthState, key)
            fifthState    = Swag.vecAesEncryptRound(fifthState, key)
            sixthState    = Swag.vecAesEncryptRound(sixthState, key)
            seventhState  = Swag.vecAesEncryptRound(seventhState, key)
            eighthState   = Swag.vecAesEncryptRound(eighthState, key)
        }

        let final = .roundKey(.rounds)
        store(destination, Swag.vecAesEncryptLastRound(firstState, final) ^ load(source))
        store(destination + AesBlockSize, Swag.vecAesEncryptLastRound(secondState, final) ^ load(source + AesBlockSize))
        store(destination + 2 * AesBlockSize, Swag.vecAesEncryptLastRound(thirdState, final) ^ load(source + 2 * AesBlockSize))
        store(destination + 3 * AesBlockSize, Swag.vecAesEncryptLastRound(fourthState, final) ^ load(source + 3 * AesBlockSize))
        store(destination + 4 * AesBlockSize, Swag.vecAesEncryptLastRound(fifthState, final) ^ load(source + 4 * AesBlockSize))
        store(destination + 5 * AesBlockSize, Swag.vecAesEncryptLastRound(sixthState, final) ^ load(source + 5 * AesBlockSize))
        store(destination + 6 * AesBlockSize, Swag.vecAesEncryptLastRound(seventhState, final) ^ load(source + 6 * AesBlockSize))
        store(destination + 7 * AesBlockSize, Swag.vecAesEncryptLastRound(eighthState, final) ^ load(source + 7 * AesBlockSize))
    }

    #[Swag.Inline]
    private mtd encryptSoftwareRound(state, key: U8x16)->U8x16
    {
        return .mixColumns(shuffle(aesTowerSubstitute(state), AesSoftwareShiftRows)) ^ key
    }

    // Encrypts two complete counters with the software key schedule.
    #[Swag.Inline]
    internal mtd xorTwoCountersSoftware(first, second: U8x16, source: const [*] u8, destination: [*] u8)
    {
        let initial = .roundKey(0)
        var state: [2] U8x16 = [aesTowerEncode(first) ^ initial, aesTowerEncode(second) ^ initial]
        for round in 1 until .rounds
        {
            let key = .roundKey(round)
            state[0] = .encryptSoftwareRound(state[0], key)
            state[1] = .encryptSoftwareRound(state[1], key)
        }

        let key = .roundKey(.rounds)
        let firstStream  = aesTowerDecode(shuffle(aesTowerSubstitute(state[0]), AesSoftwareShiftRows) ^ key)
        let secondStream = aesTowerDecode(shuffle(aesTowerSubstitute(state[1]), AesSoftwareShiftRows) ^ key)
        store(destination, firstStream ^ load(source))
        store(destination + AesBlockSize, secondStream ^ load(source + AesBlockSize))
        Crypto.secureClear(state)
    }

    #[Swag.Inline]
    internal mtd(Prepared: bool) decryptBlockHardware(value: U8x16)->U8x16
    {
        var state = value ^ .roundKey(.rounds)
        for round in 1 until .rounds
        {
            let key = .roundKey(.rounds - round)
            state = Swag.vecAesDecryptRound(state, Prepared ? key : Swag.vecAesInverseMixColumns(key))
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
        return state ^ sum ^ aesTowerDouble(difference)
    }

    #[Swag.Inline]
    private mtd inverseMixColumns(state: U8x16)->U8x16
    {
        const Opposite = cast(U8x16, [2'u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
        let correction = aesTowerDouble(aesTowerDouble(state ^ shuffle(state, Opposite)))
        return .mixColumns(state ^ correction)
    }

    // Clears the expanded key schedule when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}

#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Minimum RSA modulus size accepted by this API, in bytes (2048 bits).
public const RsaMinModulusSize = 256

// Maximum RSA modulus size accepted by this API, in bytes (4096 bits).
public const RsaMaxModulusSize = 512

// SHA-256 digest and RSA-OAEP/PSS salt size, in bytes.
public const RsaSha256Size = 32

private struct RsaMontgomery
{
    modulus:   [64] u64
    one:       [64] u64
    r2:        [64] u64
    limbCount: u32
    byteCount: u32
    n0Inverse: u64
}

private func rsaMontgomeryClear(context: *RsaMontgomery)
{
    Crypto.secureClear(context[].modulus)
    Crypto.secureClear(context[].one)
    Crypto.secureClear(context[].r2)
    context[].limbCount = 0
    context[].byteCount = 0
    context[].n0Inverse = 0
}

private func rsaReadWords(bytes: const [..] u8)->[64] u64
{
    var result: #returntype
    let fullWords = bytes.count / 8
    for index in fullWords
    {
        let offset = bytes.count - (index + 1) * 8
        var word: u64
        Swag.memcpy(&word, bytes.buffer + offset, 8)
        result[index] = Swag.byteSwap(word)
    }

    if bytes.count % 8
    {
        result[fullWords] = (cast(u64, bytes[0]) << 24) | (cast(u64, bytes[1]) << 16) |
                            (cast(u64, bytes[2]) << 8) | cast(u64, bytes[3])
    }

    return result
}

// Initialization derives this value only from the public modulus.
private func rsaDoubleModulo(value: *[64] u64, context: *RsaMontgomery)
{
    var difference: [64] u64
    var carry  = 0_u64
    var borrow = 0_u64
    for index in context[].limbCount
    {
        let word    = value[][index]
        let doubled = (word << 1) | carry
        value[][index] = doubled
        carry = word >> 63

        let modulus    = context[].modulus[index]
        let subtracted = doubled - modulus
        difference[index] = subtracted - borrow
        borrow = cast(u64, doubled < modulus) | cast(u64, subtracted < borrow)
    }

    if carry != 0 or borrow == 0
    {
        Swag.memcpy(&value[][0], &difference[0], cast(u64, context[].limbCount) * 8)
    }
}

private func rsaMontgomeryCreate(modulus: const [..] u8)->RsaMontgomery fail
{
    if modulus.count < RsaMinModulusSize or
       modulus.count > RsaMaxModulusSize or
       modulus.count % 4 or
       modulus[0] < 0x80 or
       not (modulus[modulus.count - 1] & 1)
    {
        fail Errors.BadParameterError{"RSA modulus must be an odd, full-width value between 2048 and 4096 bits"}
    }

    var result: RsaMontgomery
    result.byteCount = cast(u32, modulus.count)
    result.limbCount = cast(u32, (modulus.count + 7) / 8)
    result.modulus   = rsaReadWords(modulus)

    var inverse = 1_u64
    for 6
    {
        inverse *= 2 - result.modulus[0] * inverse
    }

    result.n0Inverse = 0_u64 - inverse

    // The modulus has its highest encoded bit set, so 2^bits mod n is 2^bits minus n.
    var borrow = 0_u64
    for index in result.limbCount
    {
        let word = 0_u64 - result.modulus[index]
        result.one[index] = word - borrow
        borrow = cast(u64, result.modulus[index] != 0) | cast(u64, word < borrow)
    }

    if result.byteCount % 8
    {
        result.one[result.limbCount - 1] &= 0xFFFFFFFF
        for 32
        {
            rsaDoubleModulo(&result.one, &result)
        }
    }

    // Raise 2^64 to the public limb count in the Montgomery domain.
    var seed = result.one
    for 64
    {
        rsaDoubleModulo(&seed, &result)
    }

    result.r2 = seed
    let highest = 31_u32 - Swag.leadingZeros(result.limbCount)
    for step in highest
    {
        result.r2 = rsaMontgomerySquare(result.r2, &result)
        let bit = highest - 1 - step
        if (result.limbCount >> bit) & 1
        {
            result.r2 = rsaMontgomeryMultiply(result.r2, seed, &result)
        }
    }

    return result
}

private func rsaDecodeNumber(bytes: const [..] u8, context: *RsaMontgomery)->[64] u64 fail
{
    if bytes.count != context[].byteCount
    {
        fail Errors.BadParameterError{"RSA integer must match the modulus width"}
    }

    let result          = rsaReadWords(bytes)
    var lessThanModulus = false
    var equalToModulus  = true
    var index           = context[].limbCount
    while index
    {
        index -= 1
        if result[index] < context[].modulus[index]
        {
            lessThanModulus = true
            equalToModulus  = false
            break
        }

        if result[index] > context[].modulus[index]
        {
            equalToModulus = false
            break
        }
    }

    if not lessThanModulus and not equalToModulus
    {
        fail Errors.BadParameterError{"RSA integer must be smaller than the modulus"}
    }

    return result
}

#[Swag.Inline]
private func rsaMultiplyAdd(left, right, addend, carry: u64)->{word: u64, carry: u64}
{
    var high: u64
    let word = Swag.mulWide(left, right, addend, carry, &high)
    return {word, high}
}

private func rsaMontgomeryMultiply(left, right: [64] u64, context: *RsaMontgomery)->[64] u64
{
    let words = context[].limbCount
    var temporary: [65] u64
    for index in words
    {
        let multiplier = right[index]
        var carry      = 0_u64
        for word in words
        {
            let product = rsaMultiplyAdd(left[word], multiplier, temporary[word], carry)
            temporary[word] = product.word
            carry = product.carry
        }

        let productTop   = temporary[words] + carry
        let productCarry = cast(u64, productTop < carry)
        let reduction    = temporary[0] * context[].n0Inverse
        carry = rsaMultiplyAdd(reduction, context[].modulus[0], temporary[0], 0).carry
        for word in 1 until words
        {
            let product = rsaMultiplyAdd(reduction, context[].modulus[word], temporary[word], carry)
            temporary[word - 1] = product.word
            carry = product.carry
        }

        let top = productTop + carry
        temporary[words - 1] = top
        temporary[words]     = productCarry + cast(u64, top < carry)
    }

    let result = rsaReduceWords(temporary[until words], temporary[words], context)
    Crypto.secureClear(temporary)
    return result
}

private func rsaReduceWords(value: const [..] u64, high: u64, context: *RsaMontgomery)->[64] u64
{
    var difference: [64] u64
    var borrow = 0_u64
    for index in value.count
    {
        let modulus = context[].modulus[index]
        let word    = value[index] - modulus
        difference[index] = word - borrow
        borrow = cast(u64, value[index] < modulus) | cast(u64, word < borrow)
    }

    var result: #returntype
    let useDifference = cast(u64, high != 0) | cast(u64, borrow == 0)
    let mask = 0_u64 - useDifference
    for index in value.count
    {
        result[index] = (difference[index] & mask) | (value[index] & ~mask)
    }

    Crypto.secureClear(difference)
    return result
}

private func rsaMontgomerySquare(value: [64] u64, context: *RsaMontgomery)->[64] u64
{
    let words = cast(u64, context[].limbCount)
    var temporary: [128] u64

    // Accumulate one triangle of cross products before doubling it.
    for row in words
    {
        var carry = 0_u64
        for column in row + 1 until words
        {
            let position = row + column
            let product  = rsaMultiplyAdd(value[row], value[column], temporary[position], carry)
            temporary[position] = product.word
            carry = product.carry
        }

        temporary[row + words] = carry
    }

    var carry = 0_u64
    for word in words * 2
    {
        let lower = temporary[word]
        temporary[word] = (lower << 1) | carry
        carry = lower >> 63
    }

    // Add one diagonal product to each adjacent pair of words.
    carry = 0
    for row in words
    {
        let word    = row * 2
        let product = rsaMultiplyAdd(value[row], value[row], temporary[word], carry)
        temporary[word] = product.word
        let high = temporary[word + 1] + product.carry
        temporary[word + 1] = high
        carry = cast(u64, high < product.carry)
    }

    // A top carry belongs to the next row's top word, above its product loop.
    var extra = 0_u64
    for row in words
    {
        let reduction = temporary[row] * context[].n0Inverse
        carry = 0
        for column in words
        {
            let position = row + column
            let product  = rsaMultiplyAdd(reduction, context[].modulus[column], temporary[position], carry)
            temporary[position] = product.word
            carry = product.carry
        }

        let top   = temporary[row + words] + carry
        let added = top + extra
        temporary[row + words] = added
        extra = cast(u64, top < carry) | cast(u64, added < extra)
    }

    let result = rsaReduceWords(temporary[words until words * 2], extra, context)
    Crypto.secureClear(temporary)
    return result
}

private func rsaExponentBit(exponent: const [..] u8, bit: u64)->u32
{
    let byte = exponent.count - 1 - (bit / 8)
    return (cast(u32, exponent[byte]) >> cast(u32, bit % 8)) & 1
}

private func rsaPrivatePower(base: [64] u64, exponent: const [..] u8, context: *RsaMontgomery)->[64] u64
{
    var powers: [16][64] u64
    powers[0] = context[].one
    powers[1] = base
    for digit in 2 until powers.count
    {
        powers[digit] = rsaMontgomeryMultiply(powers[digit - 1], base, context)
    }

    defer Crypto.secureClear(Swag.makeSlice(&powers, 1))

    var result = context[].one
    for step in context[].byteCount * 2
    {
        for 4
        {
            var squared = rsaMontgomerySquare(result, context)
            Crypto.secureClear(result)
            result = squared
            Crypto.secureClear(squared)
        }

        let shift = (1 - (step & 1)) * 4
        let digit = (exponent[step / 2] >> shift) & 15
        var selected: [64] u64
        for index in powers.count
        {
            let mask = 0_u64 - cast(u64, index == digit)
            for limb in context[].limbCount
            {
                selected[limb] |= powers[index][limb] & mask
            }
        }

        var product = rsaMontgomeryMultiply(result, selected, context)
        Crypto.secureClear(result)
        result = product
        Crypto.secureClear(selected)
        Crypto.secureClear(product)
    }

    return result
}

private func rsaPublicPower(base: [64] u64, exponent: const [..] u8, context: *RsaMontgomery)->[64] u64
{
    var bits = exponent.count * 8
    while bits and not rsaExponentBit(exponent, bits - 1)
    {
        bits -= 1
    }

    if not bits
    {
        return context[].one
    }

    var result = base
    while bits > 1
    {
        bits   -= 1
        result = rsaMontgomerySquare(result, context)
        if rsaExponentBit(exponent, bits - 1)
        {
            result = rsaMontgomeryMultiply(result, base, context)
        }
    }

    return result
}

// IFMA accumulates the low and high 52-bit halves of two products.
private const Rsa52Bits     = 52
private const Rsa52Mask     = (1_u64 << Rsa52Bits) - 1
private const Rsa52MaxWords = (RsaMaxModulusSize * 8 + Rsa52Bits - 1) / Rsa52Bits
private const Rsa52Words    = (Rsa52MaxWords + 1) & ~1
private alias Rsa52Digits = [Rsa52Words] u64

private struct Rsa52Context
{
    modulus: Rsa52Digits
    one:     Rsa52Digits
    r2:      Rsa52Digits
    words:   u64
    inverse: u64
}

private struct Rsa52Temporary
{
    low, high: [2 * Rsa52Words + 2] u64
}

private func rsa52Pack(input: const *[64] u64, sourceWords: u64, output: *Rsa52Digits, count: u64)
{
    for index in count
    {
        let offset = index * Rsa52Bits
        let word   = offset / 64
        let shift  = offset % 64
        var digit  = input[][word] >> shift
        if shift > 64 - Rsa52Bits and word + 1 < sourceWords
        {
            digit |= input[][word + 1] << (64 - shift)
        }

        output[][index] = digit & Rsa52Mask
    }
}

private func rsa52Unpack(input: const *Rsa52Digits, count, targetWords: u64)->[64] u64
{
    var output: #returntype
    for index in count
    {
        let offset = index * Rsa52Bits
        let word   = offset / 64
        let shift  = offset % 64
        let digit  = input[][index]
        output[word] |= digit << shift
        if shift > 64 - Rsa52Bits and word + 1 < targetWords
        {
            output[word + 1] |= digit >> (64 - shift)
        }
    }

    return output
}

#[Swag.Inline]
private func rsa52Accumulate(low, high: [*] u64, factor: const [*] u64, digit, count: u64)
{
    let broadcast = Simd.splat(digit)
    var column = 0_u64
    while column < count
    {
        let operands = Simd.load(factor + column)
        let lowPair  = Simd.load(low + column)
        let highPair = Simd.load(high + column)
        Simd.store(low + column, Swag.vecMultiplyAdd52Low(lowPair, operands, broadcast))
        Simd.store(high + column, Swag.vecMultiplyAdd52High(highPair, operands, broadcast))
        column += 2
    }
}

private func(Square: bool) rsa52Product(output: *Rsa52Digits, left, right: const *Rsa52Digits, context: const *Rsa52Context,
                          temporary: *Rsa52Temporary)
{
    let count     = context[].words
    let pairWords = (count + 1) & ~1_u64
    let low       = temporary[].low.buffer
    let high      = temporary[].high.buffer
    let clearSize = (count * 2 + 3) * #sizeof(u64)
    Swag.memset(low, 0, clearSize)
    Swag.memset(high, 0, clearSize)

    // Each limb sums at most twice the word count in 52-bit terms.
    // Unused vector lanes read the zero padding above the active words.
    #static if Square
    {
        // Only the cross-product triangle contributes twice.
        for index in count
        {
            let tail = (count - index) & ~1_u64
            rsa52Accumulate(low + 2 * index + 1, high + 2 * index + 2, left[].buffer + index + 1, left[][index], tail)
        }

        for index in count * 2
        {
            low[index] <<= 1
            high[index] <<= 1
        }

        for index in count
        {
            var upper: u64
            let bottom = Swag.mulWide(left[][index], left[][index], &upper)
            low[2 * index] += bottom & Rsa52Mask
            high[2 * index + 1] += (bottom >> Rsa52Bits) | (upper << (64 - Rsa52Bits))
        }
    }

    for index in count
    {
        #static if not Square
        {
            rsa52Accumulate(low + index, high + index + 1, left[].buffer, right[][index], pairWords)
        }
        let reduction = ((low[index] + high[index]) * context[].inverse) & Rsa52Mask
        rsa52Accumulate(low + index, high + index + 1, context[].modulus.buffer, reduction, pairWords)
        low[index + 1] += (low[index] + high[index]) >> Rsa52Bits
    }

    var carry  = 0_u64
    var borrow = 0_u64
    for index in count
    {
        let value = low[count + index] + high[count + index] + carry
        carry = value >> Rsa52Bits
        let word = value & Rsa52Mask
        output[][index] = word
        let difference = word - context[].modulus[index] - borrow
        borrow = difference >> 63
        low[index] = difference & Rsa52Mask
    }

    let top  = low[count * 2] + high[count * 2] + carry
    let mask = 0_u64 - (cast(u64, top != 0) | cast(u64, borrow == 0))
    for index in count
    {
        output[][index] = (low[index] & mask) | (output[][index] & ~mask)
    }
}

// The initialization only uses the public modulus and its encoded width.
private func rsa52Double(value: *Rsa52Digits, context: const *Rsa52Context)
{
    var difference: Rsa52Digits
    var carry  = 0_u64
    var borrow = 0_u64
    for index in context[].words
    {
        let doubled = (value[][index] << 1) | carry
        carry = doubled >> Rsa52Bits
        let word = doubled & Rsa52Mask
        value[][index] = word
        let reduced = word - context[].modulus[index] - borrow
        borrow = reduced >> 63
        difference[index] = reduced & Rsa52Mask
    }

    if carry or not borrow
    {
        Swag.memcpy(value[].buffer, difference.buffer, context[].words * #sizeof(u64))
    }
}

private func rsa52Initialize(result: *Rsa52Context, source: const *RsaMontgomery, temporary: *Rsa52Temporary)
{
    let bits    = cast(u64, source[].byteCount) * 8
    let count   = (bits + Rsa52Bits - 1) / Rsa52Bits
    let padding = count * Rsa52Bits - bits
    result[].words = count
    result[].inverse = source[].n0Inverse & Rsa52Mask
    rsa52Pack(&source[].modulus, source[].limbCount, &result[].modulus, count)

    // The modulus is full width. Subtract it from 2^bits and extend to R.
    var borrow = 0_u64
    for index in count
    {
        let word = 0_u64 - result[].modulus[index] - borrow
        borrow = word >> 63
        result[].one[index] = word & Rsa52Mask
    }

    result[].one[count - 1] &= Rsa52Mask >> padding
    for padding
    {
        rsa52Double(&result[].one, result)
    }

    var seed = result[].one
    for Rsa52Bits
    {
        rsa52Double(&seed, result)
    }

    // Raise 2^52 to the public word count in the Montgomery domain.
    result[].r2 = seed
    let highest = 63_u64 - Swag.leadingZeros(count)
    for step in highest
    {
        rsa52Product!{true}(&result[].r2, &result[].r2, &result[].r2, result, temporary)
        if (count >> (highest - step - 1)) & 1
        {
            rsa52Product!{false}(&result[].r2, &result[].r2, &seed, result, temporary)
        }
    }
}

private struct Rsa52PrivateStorage
{
    temporary: Rsa52Temporary
    powers:    [16] Rsa52Digits
    working:   Rsa52Digits
    selection: Rsa52Digits
}

private func rsa52PrivatePower(input: const *[64] u64, exponent: const [..] u8,
                              source: const *RsaMontgomery)->[64] u64
{
    var context: Rsa52Context
    var scratch: Rsa52PrivateStorage
    defer Crypto.secureClear(Swag.makeSlice(&scratch, 1))
    rsa52Initialize(&context, source, &scratch.temporary)

    scratch.powers[0] = context.one
    rsa52Pack(input, source[].limbCount, &scratch.powers[1], context.words)
    rsa52Product!{false}(&scratch.powers[1], &scratch.powers[1], &context.r2, &context, &scratch.temporary)
    for digit in 2 until scratch.powers.count
    {
        rsa52Product!{false}(&scratch.powers[digit], &scratch.powers[digit - 1], &scratch.powers[1], &context, &scratch.temporary)
    }

    scratch.working = context.one
    for step in source[].byteCount * 2
    {
        for 4
        {
            rsa52Product!{true}(&scratch.working, &scratch.working, &scratch.working, &context, &scratch.temporary)
        }

        let shift = (1 - (step & 1)) * 4
        let digit = (exponent[step / 2] >> shift) & 15
        Swag.memset(scratch.selection.buffer, 0, context.words * #sizeof(u64))
        for index in scratch.powers.count
        {
            let mask = 0_u64 - cast(u64, index == digit)
            for word in context.words
            {
                scratch.selection[word] |= scratch.powers[index][word] & mask
            }
        }

        rsa52Product!{false}(&scratch.working, &scratch.working, &scratch.selection, &context, &scratch.temporary)
    }

    var one: Rsa52Digits
    one[0] = 1
    rsa52Product!{false}(&scratch.working, &scratch.working, &one, &context, &scratch.temporary)
    return rsa52Unpack(&scratch.working, context.words, source[].limbCount)
}

private func rsaModularPower(base: [64] u64, exponent: const [..] u8, fixedTime: bool, context: *RsaMontgomery)->[64] u64
{
    if fixedTime and Swag.hasCpuFeature(.MultiplyAdd52)
    {
        return rsa52PrivatePower(&base, exponent, context)
    }

    var one: [64] u64
    one[0] = 1
    var baseMontgomery = rsaMontgomeryMultiply(base, context[].r2, context)
    defer Crypto.secureClear(baseMontgomery)
    var result = fixedTime ? rsaPrivatePower(baseMontgomery, exponent, context) : rsaPublicPower(baseMontgomery, exponent, context)
    defer Crypto.secureClear(result)
    return rsaMontgomeryMultiply(result, one, context)
}

private func rsaEncodeNumber(value: [64] u64, context: *RsaMontgomery)->[512] u8
{
    var result: #returntype
    let fullWords = context[].byteCount / 8
    for index in fullWords
    {
        let offset = context[].byteCount - (cast(u32, index + 1) * 8)
        let word   = Swag.byteSwap(value[index])
        Swag.memcpy(&result[offset], &word, 8)
    }

    if context[].byteCount % 8
    {
        let word = cast(u32, value[fullWords])
        result[0] = Math.byteAt(word, 3)
        result[1] = Math.byteAt(word, 2)
        result[2] = Math.byteAt(word, 1)
        result[3] = Math.byteAt(word, 0)
    }

    return result
}

private func rsaApplyWithContext(modulus, exponent, input: const [..] u8, privateOperation: bool, context: *RsaMontgomery)->[512] u8 fail
{
    if exponent.count == 0 or exponent.count > modulus.count
    {
        fail Errors.BadParameterError{"RSA exponent must be a nonempty value no wider than the modulus"}
    }

    if privateOperation and exponent.count != modulus.count
    {
        fail Errors.BadParameterError{"RSA private exponent must match the modulus width"}
    }

    if privateOperation
    {
        var nonzero = 0_u8
        var less    = 0_u8
        var greater = 0_u8
        for index in modulus.count
        {
            nonzero |= exponent[index]
            let undecided = 1_u8 ^ (less | greater)
            let smaller   = cast(u8, exponent[index] < modulus[index])
            let larger    = cast(u8, exponent[index] > modulus[index])
            less    |= undecided & smaller
            greater |= undecided & larger
        }

        if nonzero == 0 or less == 0
        {
            fail Errors.BadParameterError{"RSA private exponent must be a nonzero value smaller than the modulus"}
        }
    }

    if not privateOperation and
       ((exponent[exponent.count - 1] & 1) == 0 or
        (exponent.count == 1 and exponent[0] < 3))
    {
        fail Errors.BadParameterError{"RSA public exponent must be an odd integer greater than one"}
    }

    let decoded = try rsaDecodeNumber(input, context)
    let powered = rsaModularPower(decoded, exponent, privateOperation, context)
    let result  = rsaEncodeNumber(powered, context)
    Crypto.secureClear(decoded)
    Crypto.secureClear(powered)
    return result
}

private func rsaApply(modulus, exponent, input: const [..] u8, privateOperation: bool)->[512] u8 fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    return try rsaApplyWithContext(modulus, exponent, input, privateOperation, &context)
}

private func rsaSha256(data: const [..] u8)->[32] u8
{
    let digest = Hash.Sha256.compute(data)
    var result: #returntype
    for index in 8
    {
        result[index * 4]     = Math.byteAt(digest[index], 3)
        result[index * 4 + 1] = Math.byteAt(digest[index], 2)
        result[index * 4 + 2] = Math.byteAt(digest[index], 1)
        result[index * 4 + 3] = Math.byteAt(digest[index], 0)
    }

    return result
}

private func rsaMgf1Sha256(seed: const [..] u8, destination: [..] u8)
{
    var counter = 0_u32
    var offset  = 0_u64
    while offset < destination.count
    {
        var hash: Hash.Sha256
        hash.update(seed)
        var encodedCounter: [4] u8
        encodedCounter[0] = Math.byteAt(counter, 3)
        encodedCounter[1] = Math.byteAt(counter, 2)
        encodedCounter[2] = Math.byteAt(counter, 1)
        encodedCounter[3] = Math.byteAt(counter, 0)
        hash.update(encodedCounter)
        let digest = rsaSha256Bytes(hash.finalize())
        let count  = Math.min(destination.count - offset, RsaSha256Size)
        Swag.memcpy(destination.buffer + offset, &digest[0], count)
        hash.reset()
        Crypto.secureClear(encodedCounter)
        Crypto.secureClear(digest)
        offset  += count
        counter += 1
    }
}

private func rsaSha256Bytes(digest: Hash.Sha256.Digest)->[32] u8
{
    var result: #returntype
    for index in 8
    {
        result[index * 4]     = Math.byteAt(digest[index], 3)
        result[index * 4 + 1] = Math.byteAt(digest[index], 2)
        result[index * 4 + 2] = Math.byteAt(digest[index], 1)
        result[index * 4 + 3] = Math.byteAt(digest[index], 0)
    }

    return result
}

private func rsaValidPublicExponent(exponent: const [..] u8)->bool
{
    if exponent.count == 0
    {
        return false
    }

    var nonzero       = false
    var higherNonzero = false
    for byte in exponent.count
    {
        nonzero = nonzero or exponent[byte] != 0
        if byte + 1 < exponent.count
        {
            higherNonzero = higherNonzero or exponent[byte] != 0
        }
    }

    return nonzero and
           (exponent[exponent.count - 1] & 1) != 0 and
           (higherNonzero or exponent[exponent.count - 1] >= 3)
}

private func rsaLessThan(left, right: const [..] u8)->bool
{
    if left.count != right.count
    {
        return left.count < right.count
    }

    for index in left.count
    {
        if left[index] < right[index]
        {
            return true
        }

        if left[index] > right[index]
        {
            return false
        }
    }

    return false
}

private func rsaValidatePublicKey(modulus, exponent: const [..] u8) fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if not rsaValidPublicExponent(exponent) or
       exponent.count > modulus.count or
       not rsaLessThan(exponent, modulus)
    {
        fail Errors.BadParameterError{"RSA public exponent must be an odd integer greater than one and smaller than the modulus"}
    }
}

// Encrypts a message with RSAES-OAEP using SHA-256 and MGF1-SHA-256 (RFC 8017).
//
// `modulus` is an unsigned big-endian integer from 256 through 512 bytes; `publicExponent` is an
// unsigned big-endian integer such as 65537. Ciphertext must be exactly the modulus width. Labels
// are authenticated context, not encrypted metadata. The message limit is modulus width minus
// 66 bytes. Fails with [[Core.Errors.BadParameterError]] for invalid key or buffer sizes.
public func rsaOaepSha256Encrypt(modulus, publicExponent, plaintext, label: const [..] u8, ciphertext: [..] u8) fail
{
    try rsaValidatePublicKey(modulus, publicExponent)
    let width = modulus.count
    if ciphertext.count != width or
       width < 2 * RsaSha256Size + 2 or
       plaintext.count > width - 2 * RsaSha256Size - 2
    {
        fail Errors.BadParameterError{"RSA-OAEP needs a modulus-width output and a message at most modulus-width minus 66 bytes"}
    }

    var encoded: [512] u8
    defer Crypto.secureClear(encoded)
    let dataLength = width - RsaSha256Size - 1
    let labelHash  = rsaSha256(label)
    defer Crypto.secureClear(labelHash)
    Swag.memcpy(&encoded[33], &labelHash[0], RsaSha256Size)
    let delimiter = dataLength - plaintext.count - 1
    encoded[33 + delimiter] = 1
    if plaintext.count
    {
        Swag.memcpy(&encoded[34 + delimiter], plaintext.buffer, plaintext.count)
    }

    var seed: [RsaSha256Size] u8
    defer Crypto.secureClear(seed)
    try Crypto.randomBytes(seed)
    var dataMask: [512] u8
    defer Crypto.secureClear(dataMask)
    rsaMgf1Sha256(seed, dataMask[0 until dataLength])
    for index in dataLength
    {
        encoded[33 + index] ^= dataMask[index]
    }

    var seedMask: [RsaSha256Size] u8
    defer Crypto.secureClear(seedMask)
    rsaMgf1Sha256(encoded[33 until width], seedMask)
    for index in RsaSha256Size
    {
        encoded[1 + index] = seed[index] ^ seedMask[index]
    }

    var result = try rsaApply(modulus, publicExponent, encoded[0 until width], false)
    defer Crypto.secureClear(result)
    Swag.memcpy(ciphertext.buffer, &result[0], width)
}

// Decrypts RSAES-OAEP with SHA-256 and MGF1-SHA-256 (RFC 8017).
//
// `modulus`, `privateExponent`, and `ciphertext` are unsigned big-endian integers exactly the
// modulus width. `plaintext` must hold up to modulus width minus 66 bytes; the return value gives
// the actual message length. A malformed ciphertext or OAEP encoding fails with one generic
// [[Core.Errors.BadParameterError]] and leaves the destination untouched.
public func rsaOaepSha256Decrypt(modulus, privateExponent, ciphertext, label: const [..] u8, plaintext: [..] u8)->u64 fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if ciphertext.count != context.byteCount or
       privateExponent.count != context.byteCount or
       plaintext.count < context.byteCount - (2 * RsaSha256Size + 2)
    {
        fail Errors.BadParameterError{"RSA-OAEP needs modulus-width key and ciphertext values and a maximum-size plaintext destination"}
    }

    if not rsaLessThan(ciphertext, modulus)
    {
        fail Errors.BadParameterError{"RSA-OAEP decoding failed"}
    }

    var encoded = try rsaApplyWithContext(modulus, privateExponent, ciphertext, true, &context)
    defer Crypto.secureClear(encoded)
    let width      = context.byteCount
    let dataLength = width - RsaSha256Size - 1
    var seed: [RsaSha256Size] u8
    defer Crypto.secureClear(seed)
    var seedMask: [RsaSha256Size] u8
    defer Crypto.secureClear(seedMask)
    var dataMask: [512] u8
    defer Crypto.secureClear(dataMask)
    var dataBlock: [512] u8
    defer Crypto.secureClear(dataBlock)
    rsaMgf1Sha256(encoded[33 until width], seedMask)
    for index in RsaSha256Size
    {
        seed[index] = encoded[1 + index] ^ seedMask[index]
    }

    rsaMgf1Sha256(seed, dataMask[0 until dataLength])
    for index in dataLength
    {
        dataBlock[index] = encoded[33 + index] ^ dataMask[index]
    }

    let labelHash = rsaSha256(label)
    defer Crypto.secureClear(labelHash)
    var invalid = cast(u8, encoded[0] != 0)
    invalid |= cast(u8, not Crypto.constantTimeEqual(dataBlock[0 until RsaSha256Size], labelHash))
    var lookingForDelimiter = 1_u8
    var messageOffset       = 0_u64
    for index in RsaSha256Size until dataLength
    {
        let byte   = dataBlock[index]
        let isZero = cast(u8, byte == 0)
        let isOne  = cast(u8, byte == 1)
        invalid |= lookingForDelimiter & (1 ^ (isZero | isOne))
        let foundDelimiter = lookingForDelimiter & isOne
        let mask = 0_u64 - foundDelimiter
        messageOffset       = (messageOffset & ~mask) | ((index + 1) & mask)
        lookingForDelimiter &= isZero
    }

    invalid |= lookingForDelimiter
    if invalid
    {
        fail Errors.BadParameterError{"RSA-OAEP decoding failed"}
    }

    let messageLength = dataLength - messageOffset
    if messageLength
    {
        Swag.memcpy(plaintext.buffer, &dataBlock[messageOffset], messageLength)
    }

    return messageLength
}

// Signs with RSASSA-PSS using SHA-256 and a random 32-byte salt (RFC 8017).
//
// Modulus and private exponent are unsigned big-endian values; the private exponent and signature
// are exactly the modulus width. The key must be 2048 through 4096 bits. A fresh cryptographic
// salt is generated for every call. Fails with [[Core.Errors.BadParameterError]] for invalid
// key or output sizes and [[Swag.SystemError]] if secure randomness fails.
public func rsaPssSha256Sign(modulus, privateExponent, message: const [..] u8, signature: [..] u8) fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if privateExponent.count != context.byteCount or signature.count != context.byteCount
    {
        fail Errors.BadParameterError{"RSA-PSS needs modulus-width private exponent and signature values"}
    }

    let width         = context.byteCount
    let dataLength    = width - RsaSha256Size - 1
    let paddingLength = width - (2 * RsaSha256Size) - 2
    let messageHash   = rsaSha256(message)
    defer Crypto.secureClear(messageHash)
    var salt: [RsaSha256Size] u8
    defer Crypto.secureClear(salt)
    try Crypto.randomBytes(salt)

    var hashInput: [8 + 2 * RsaSha256Size] u8
    defer Crypto.secureClear(hashInput)
    Swag.memcpy(&hashInput[8], &messageHash[0], RsaSha256Size)
    Swag.memcpy(&hashInput[8 + RsaSha256Size], &salt[0], RsaSha256Size)
    let encodedHash = rsaSha256(hashInput)
    defer Crypto.secureClear(encodedHash)

    var dataBlock: [512] u8
    defer Crypto.secureClear(dataBlock)
    dataBlock[paddingLength] = 1
    Swag.memcpy(&dataBlock[paddingLength + 1], &salt[0], RsaSha256Size)
    var mask: [512] u8
    defer Crypto.secureClear(mask)
    rsaMgf1Sha256(encodedHash, mask[0 until dataLength])
    var encoded: [512] u8
    defer Crypto.secureClear(encoded)
    for index in dataLength
    {
        encoded[index] = dataBlock[index] ^ mask[index]
    }

    encoded[0] &= 0x7F
    Swag.memcpy(&encoded[dataLength], &encodedHash[0], RsaSha256Size)
    encoded[width - 1] = 0xBC

    var result = try rsaApplyWithContext(modulus, privateExponent, encoded[0 until width], true, &context)
    defer Crypto.secureClear(result)
    Swag.memcpy(signature.buffer, &result[0], width)
}

// Verifies an RSASSA-PSS SHA-256 signature with a 32-byte salt (RFC 8017).
//
// Returns false for an invalid signature. Modulus and public exponent are unsigned big-endian
// values, and signature is exactly the modulus width. Invalid key material or widths fail with
// [[Core.Errors.BadParameterError]].
public func rsaPssSha256Verify(modulus, publicExponent, message, signature: const [..] u8)->bool fail
{
    try rsaValidatePublicKey(modulus, publicExponent)
    if signature.count != modulus.count or not rsaLessThan(signature, modulus)
    {
        return false
    }

    var encoded = try rsaApply(modulus, publicExponent, signature, false)
    defer Crypto.secureClear(encoded)
    let width         = modulus.count
    let dataLength    = width - RsaSha256Size - 1
    let paddingLength = width - (2 * RsaSha256Size) - 2
    var invalid       = cast(u8, encoded[width - 1] != 0xBC or (encoded[0] & 0x80) != 0)
    var mask: [512] u8
    rsaMgf1Sha256(encoded[dataLength until dataLength + RsaSha256Size], mask[0 until dataLength])
    var dataBlock: [512] u8
    for index in dataLength
    {
        dataBlock[index] = encoded[index] ^ mask[index]
    }

    dataBlock[0] &= 0x7F
    for index in paddingLength
    {
        invalid |= cast(u8, dataBlock[index] != 0)
    }

    invalid |= cast(u8, dataBlock[paddingLength] != 1)

    let messageHash = rsaSha256(message)
    var hashInput: [8 + 2 * RsaSha256Size] u8
    Swag.memcpy(&hashInput[8], &messageHash[0], RsaSha256Size)
    Swag.memcpy(&hashInput[8 + RsaSha256Size], &dataBlock[paddingLength + 1], RsaSha256Size)
    let expectedHash = rsaSha256(hashInput)
    let valid        = invalid == 0 and Crypto.constantTimeEqual(expectedHash, encoded[dataLength until dataLength + RsaSha256Size])
    Crypto.secureClear(mask)
    Crypto.secureClear(dataBlock)
    Crypto.secureClear(messageHash)
    Crypto.secureClear(hashInput)
    Crypto.secureClear(expectedHash)
    return valid
}

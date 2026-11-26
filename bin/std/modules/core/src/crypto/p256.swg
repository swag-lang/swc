#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// P-256 private scalar and coordinate size in bytes.
public const P256ScalarSize = 32

// P-256 uncompressed public key size in bytes, including the 0x04 prefix.
public const P256PublicKeySize = 65

private struct P256Field
{
    limbs: [8] u32
}

private struct P256Point
{
    x: P256Field
    y: P256Field
    z: P256Field
}

private const P256Modulus: [8] u32 = [
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0xFFFFFFFF]

private const P256Order: [8] u32 = [
    0xFC632551, 0xF3B9CAC2, 0xA7179E84, 0xBCE6FAAD,
    0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF]

private const P256MontgomeryOne: [8] u32 = [
    0x00000001, 0x00000000, 0x00000000, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0x00000000]

private const P256MontgomeryR2: [8] u32 = [
    0x00000003, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFB,
    0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFD, 0x00000004]

private const P256OrderMontgomeryOne: [8] u32 = [
    0x039CDAAF, 0x0C46353D, 0x58E8617B, 0x43190552,
    0x00000000, 0x00000000, 0xFFFFFFFF, 0x00000000]

private const P256OrderMontgomeryR2: [8] u32 = [
    0xBE79EEA2, 0x83244C95, 0x49BD6FA6, 0x4699799C,
    0x2B6BEC59, 0x2845B239, 0xF3D95620, 0x66E12D94]

private const P256OrderInverseExponent: [8] u32 = [
    0xFC63254F, 0xF3B9CAC2, 0xA7179E84, 0xBCE6FAAD,
    0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF]

private const P256OrderWordInverse = 0xCCD1C8AAEE00BC4F'u64

#[Swag.Inline]
private func p256MultiplyAdd(left, right, addend, carry: u64)->{word: u64, carry: u64}
{
    let product = Math.mulU64(left, right)
    let sum     = product.lo + addend
    let word    = sum + carry
    let high    = product.hi + cast(u64, sum < product.lo) + cast(u64, word < sum)
    return {word, high}
}

private func p256MontgomeryMultiply(left, right, modulus: [8] u32, n0Inverse: u64)->[8] u32
{
    var leftWords, rightWords, modulusWords: [4] u64
    for index in 4
    {
        leftWords[index]    = left[index * 2] | (cast(u64, left[index * 2 + 1]) << 32)
        rightWords[index]   = right[index * 2] | (cast(u64, right[index * 2 + 1]) << 32)
        modulusWords[index] = modulus[index * 2] | (cast(u64, modulus[index * 2 + 1]) << 32)
    }

    var temporary: [5] u64
    for multiplier in rightWords
    {
        var carry = 0'u64
        for word in 4
        {
            let product = p256MultiplyAdd(leftWords[word], multiplier, temporary[word], carry)
            temporary[word] = product.word
            carry = product.carry
        }

        let productTop   = temporary[4] + carry
        let productCarry = cast(u64, productTop < carry)
        let reduction    = temporary[0] * n0Inverse
        carry = p256MultiplyAdd(reduction, modulusWords[0], temporary[0], 0).carry
        for word in 1 until 4
        {
            let product = p256MultiplyAdd(reduction, modulusWords[word], temporary[word], carry)
            temporary[word - 1] = product.word
            carry = product.carry
        }

        // Retain the carry from both top-word additions before shifting off word zero.
        let top = productTop + carry
        temporary[3] = top
        temporary[4] = productCarry + cast(u64, top < carry)
    }

    var difference: [4] u64
    var borrow = 0'u64
    for index in 4
    {
        let word = temporary[index] - modulusWords[index]
        difference[index] = word - borrow
        borrow = cast(u64, temporary[index] < modulusWords[index]) | cast(u64, word < borrow)
    }

    let useDifference = cast(u64, temporary[4] != 0) | cast(u64, borrow == 0)
    let mask = 0'u64 - useDifference
    var result: #returntype
    for index in 4
    {
        let word = (difference[index] & mask) | (temporary[index] & ~mask)
        result[index * 2]     = cast(u32, word)
        result[index * 2 + 1] = cast(u32, word >> 32)
    }

    Crypto.secureClear(leftWords)
    Crypto.secureClear(rightWords)
    Crypto.secureClear(temporary)
    Crypto.secureClear(difference)
    return result
}

private func p256ToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, P256MontgomeryR2, P256Modulus, 1)
    return result
}

private func p256FromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0, 0, 0, 0, 0], P256Modulus, 1)
    return result
}

private func p256FieldAdd(left, right: P256Field)->P256Field
{
    var sum: [8] u32
    var carry = 0'u64
    for index in 8
    {
        let word = cast(u64, left.limbs[index]) + right.limbs[index] + carry
        sum[index] = cast(u32, word)
        carry      = word >> 32
    }

    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Modulus[index]) + borrow
        let word       = cast(u64, sum[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let useDifference = cast(u32, carry != 0) | cast(u32, borrow == 0)
    let mask = 0'u32 - useDifference
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (difference[index] & mask) | (sum[index] & ~mask)
    return result
}

private func p256FieldSubtract(left, right: P256Field)->P256Field
{
    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, right.limbs[index]) + borrow
        let word       = cast(u64, left.limbs[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    var corrected: [8] u32
    var carry = 0'u64
    for index in 8
    {
        let word = cast(u64, difference[index]) + P256Modulus[index] + carry
        corrected[index] = cast(u32, word)
        carry = word >> 32
    }

    let mask = 0'u32 - cast(u32, borrow)
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (corrected[index] & mask) | (difference[index] & ~mask)
    return result
}

private func p256FieldMultiply(left, right: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(left.limbs, right.limbs, P256Modulus, 1)
    return result
}

private func p256FieldSquare(value: P256Field)->P256Field => p256FieldMultiply(value, value)

private func p256FieldDouble(value: P256Field)->P256Field => p256FieldAdd(value, value)

private func p256FieldTriple(value: P256Field)->P256Field => p256FieldAdd(p256FieldDouble(value), value)

private func p256FieldEqual(left, right: P256Field)->bool
{
    var difference = 0'u32
    for index in 8 do
        difference |= left.limbs[index] ^ right.limbs[index]
    return difference == 0
}

private func p256FieldSelect(left, right: P256Field, selectRight: bool)->P256Field
{
    let mask = 0'u32 - cast(u32, selectRight)
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (right.limbs[index] & mask) | (left.limbs[index] & ~mask)
    return result
}

private func p256FieldSquareRepeated(value: P256Field, count: u32)->P256Field
{
    var result = value
    for count do
        result = p256FieldSquare(result)
    return result
}

private func p256FieldInverse(value: P256Field)->P256Field
{
    // Build powers with exponents of the form 2^n - 1. The same 30-bit
    // prefix supplies both the leading word and the shortened low word.
    var powers: [5] P256Field
    powers[0] = p256FieldMultiply(p256FieldSquare(value), value)
    powers[1] = p256FieldMultiply(p256FieldSquareRepeated(powers[0], 2), powers[0])
    powers[2] = p256FieldMultiply(p256FieldSquareRepeated(powers[1], 4), powers[1])
    var prefix = p256FieldMultiply(p256FieldSquareRepeated(powers[2], 8), powers[2])
    prefix = p256FieldMultiply(p256FieldSquareRepeated(prefix, 8), powers[2])
    prefix = p256FieldMultiply(p256FieldSquareRepeated(prefix, 4), powers[1])
    prefix = p256FieldMultiply(p256FieldSquareRepeated(prefix, 2), powers[0])

    prefix    = p256FieldSquareRepeated(prefix, 2)
    powers[3] = p256FieldMultiply(prefix, powers[0])
    powers[4] = p256FieldMultiply(prefix, value)

    // Read the exponent p - 2 as eight 32-bit words, most significant first.
    prefix = p256FieldMultiply(p256FieldSquareRepeated(powers[3], 32), value)
    prefix = p256FieldMultiply(p256FieldSquareRepeated(prefix, 128), powers[3])
    prefix = p256FieldMultiply(p256FieldSquareRepeated(prefix, 32), powers[3])
    let result = p256FieldMultiply(p256FieldSquareRepeated(prefix, 32), powers[4])

    Crypto.secureClear(powers)
    Crypto.secureClear(Swag.makeSlice(&prefix, 1))
    return result
}

private func p256OrderAdd(left, right: P256Field)->P256Field
{
    var sum: [8] u32
    var carry = 0'u64
    for index in 8
    {
        let word = cast(u64, left.limbs[index]) + right.limbs[index] + carry
        sum[index] = cast(u32, word)
        carry      = word >> 32
    }

    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, sum[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let mask = 0'u32 - (cast(u32, carry != 0) | cast(u32, borrow == 0))
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (difference[index] & mask) | (sum[index] & ~mask)
    return result
}

private func p256OrderSubtract(left, right: P256Field)->P256Field
{
    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, right.limbs[index]) + borrow
        let word       = cast(u64, left.limbs[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    var corrected: [8] u32
    var carry = 0'u64
    for index in 8
    {
        let word = cast(u64, difference[index]) + P256Order[index] + carry
        corrected[index] = cast(u32, word)
        carry = word >> 32
    }

    let mask = 0'u32 - cast(u32, borrow)
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (corrected[index] & mask) | (difference[index] & ~mask)
    return result
}

private func p256OrderMultiply(left, right: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(left.limbs, right.limbs, P256Order, P256OrderWordInverse)
    return result
}

private func p256OrderToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, P256OrderMontgomeryR2, P256Order, P256OrderWordInverse)
    return result
}

private func p256OrderFromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0, 0, 0, 0, 0], P256Order, P256OrderWordInverse)
    return result
}

private func p256OrderPower(value: P256Field, exponent: [8] u32)->P256Field
{
    var result: P256Field
    result.limbs = P256OrderMontgomeryOne
    for step in 256
    {
        let bit = 255 - step
        result = p256OrderMultiply(result, result)
        if (exponent[bit / 32] >> (bit % 32)) & 1 do
            result = p256OrderMultiply(result, value)
    }

    return result
}

private func p256OrderReduce(value: P256Field)->P256Field
{
    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, value.limbs[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let mask = 0'u32 - cast(u32, borrow == 0)
    var result: #returntype
    for index in 8 do
        result.limbs[index] = (difference[index] & mask) | (value.limbs[index] & ~mask)
    return result
}

private func p256OrderEncode(value: P256Field, destination: [..] u8)
{
    for index in 8
    {
        let offset = destination.count - (cast(u64, index + 1) * 4)
        destination[offset]     = Math.byteAt(value.limbs[index], 3)
        destination[offset + 1] = Math.byteAt(value.limbs[index], 2)
        destination[offset + 2] = Math.byteAt(value.limbs[index], 1)
        destination[offset + 3] = Math.byteAt(value.limbs[index], 0)
    }
}

private func p256ScalarIsValid(value: P256Field)->bool
{
    var borrow  = 0'u64
    var nonZero = 0'u32
    for word in value.limbs do
        nonZero |= word
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, value.limbs[index]) - subtrahend
        borrow = word >> 63
    }

    return borrow != 0 and nonZero != 0
}

private func p256DigestBytes(digest: Hash.Sha256.Digest)->[32] u8
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 4 do
            result[index * 4 + byte] = Math.byteAt(digest[index], 3 - byte)
    }

    return result
}

private func p256Rfc6979Nonce(privateScalar: P256Field, digest: [32] u8)->[32] u8 fail
{
    var key:   [32] u8
    var value: [32] u8
    Memory.set(&value[0], 1'u8, value.count)
    var scalarBytes: [32] u8
    p256OrderEncode(privateScalar, scalarBytes)

    var input: Array'u8
    input.add(value)
    input.add(0'u8)
    input.add(scalarBytes)
    input.add(digest)
    key = HmacSha256.compute(key, input.toSlice())
    Crypto.secureClear(input.toSlice())

    input.resize(0)
    input.add(value)
    value = HmacSha256.compute(key, input.toSlice())
    Crypto.secureClear(input.toSlice())

    input.resize(0)
    input.add(value)
    input.add(1'u8)
    input.add(scalarBytes)
    input.add(digest)
    key = HmacSha256.compute(key, input.toSlice())
    Crypto.secureClear(input.toSlice())

    input.resize(0)
    input.add(value)
    value = HmacSha256.compute(key, input.toSlice())
    Crypto.secureClear(input.toSlice())

    while true
    {
        input.resize(0)
        input.add(value)
        value = HmacSha256.compute(key, input.toSlice())
        Crypto.secureClear(input.toSlice())
        var candidate: P256Field
        for index in 8
        {
            let offset = 28 - (index * 4)
            candidate.limbs[index] = (cast(u32, value[offset]) << 24) |
                                     (cast(u32, value[offset + 1]) << 16) |
                                     (cast(u32, value[offset + 2]) << 8) |
                                     cast(u32, value[offset + 3])
        }

        if p256ScalarIsValid(candidate)
        {
            let result = value
            Crypto.secureClear(Swag.makeSlice(&key, 1))
            Crypto.secureClear(Swag.makeSlice(&value, 1))
            Crypto.secureClear(Swag.makeSlice(&scalarBytes, 1))
            Crypto.secureClear(Swag.makeSlice(&candidate, 1))
            return result
        }

        Crypto.secureClear(Swag.makeSlice(&candidate, 1))

        input.resize(0)
        input.add(value)
        input.add(0'u8)
        key = HmacSha256.compute(key, input.toSlice())
        Crypto.secureClear(input.toSlice())
        input.resize(0)
        input.add(value)
        value = HmacSha256.compute(key, input.toSlice())
        Crypto.secureClear(input.toSlice())
    }
}

private func p256FieldDecode(bytes: const [..] u8)->P256Field fail
{
    if bytes.count != P256ScalarSize do
        fail Errors.BadParameterError{"P-256 coordinates and scalars must be 32 bytes"}
    var result: #returntype
    for index in 8
    {
        let offset = bytes.count - (cast(u64, index + 1) * 4)
        result.limbs[index] = (cast(u32, bytes[offset]) << 24) |
                              (cast(u32, bytes[offset + 1]) << 16) |
                              (cast(u32, bytes[offset + 2]) << 8) |
                              cast(u32, bytes[offset + 3])
    }

    var lessThanModulus = false
    var index = 8'u32
    while index
    {
        index -= 1
        if result.limbs[index] < P256Modulus[index]
        {
            lessThanModulus = true
            break
        }

        if result.limbs[index] > P256Modulus[index]
        {
            break
        }
    }

    if not lessThanModulus do
        fail Errors.BadParameterError{"P-256 coordinate must be smaller than the field modulus"}
    return p256ToMontgomery(result)
}

private func p256ReadInteger(bytes: const [..] u8)->P256Field
{
    var result: #returntype
    for index in 8
    {
        let offset = bytes.count - (cast(u64, index + 1) * 4)
        result.limbs[index] = (cast(u32, bytes[offset]) << 24) |
                              (cast(u32, bytes[offset + 1]) << 16) |
                              (cast(u32, bytes[offset + 2]) << 8) |
                              cast(u32, bytes[offset + 3])
    }

    return result
}

private func p256ScalarDecode(bytes: const [..] u8)->P256Field fail
{
    if bytes.count != P256ScalarSize do
        fail Errors.BadParameterError{"P-256 private scalar must be 32 bytes"}
    var result: #returntype
    for index in 8
    {
        let offset = bytes.count - (cast(u64, index + 1) * 4)
        result.limbs[index] = (cast(u32, bytes[offset]) << 24) |
                              (cast(u32, bytes[offset + 1]) << 16) |
                              (cast(u32, bytes[offset + 2]) << 8) |
                              cast(u32, bytes[offset + 3])
    }

    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, result.limbs[index]) - subtrahend
        borrow = word >> 63
    }

    var nonZero = 0'u32
    for word in result.limbs do
        nonZero |= word
    if borrow == 0 or not nonZero do
        fail Errors.BadParameterError{"P-256 private scalar must be between 1 and the curve order minus one"}
    return result
}

private func p256FieldEncode(value: P256Field, destination: [..] u8)
{
    var ordinary = p256FromMontgomery(value)
    for index in 8
    {
        let word   = ordinary.limbs[index]
        let offset = destination.count - (cast(u64, index + 1) * 4)
        destination[offset]     = Math.byteAt(word, 3)
        destination[offset + 1] = Math.byteAt(word, 2)
        destination[offset + 2] = Math.byteAt(word, 1)
        destination[offset + 3] = Math.byteAt(word, 0)
    }

    Crypto.secureClear(Swag.makeSlice(&ordinary, 1))
}

private func p256Infinity()->P256Point => P256Point{}

private func p256PointSelect(left, right: P256Point, selectRight: bool)->P256Point
{
    var result: #returntype
    result.x = p256FieldSelect(left.x, right.x, selectRight)
    result.y = p256FieldSelect(left.y, right.y, selectRight)
    result.z = p256FieldSelect(left.z, right.z, selectRight)
    return result
}

private func p256PointDouble(point: P256Point)->P256Point
{
    let delta = p256FieldSquare(point.z)
    let gamma = p256FieldSquare(point.y)
    let beta  = p256FieldMultiply(point.x, gamma)
    let alpha = p256FieldTriple(p256FieldMultiply(p256FieldSubtract(point.x, delta), p256FieldAdd(point.x, delta)))

    var result: P256Point
    let alphaSquared = p256FieldSquare(alpha)
    let fourBeta     = p256FieldDouble(p256FieldDouble(beta))
    let eightBeta    = p256FieldDouble(fourBeta)
    result.x = p256FieldSubtract(alphaSquared, eightBeta)

    let gammaSquared      = p256FieldSquare(gamma)
    let eightGammaSquared = p256FieldDouble(p256FieldDouble(p256FieldDouble(gammaSquared)))
    result.y = p256FieldSubtract(p256FieldMultiply(alpha, p256FieldSubtract(fourBeta, result.x)), eightGammaSquared)
    result.z = p256FieldDouble(p256FieldMultiply(point.y, point.z))
    return result
}

private func p256PointAdd(left, right, doubled: P256Point)->P256Point
{
    let z1Squared = p256FieldSquare(left.z)
    let z2Squared = p256FieldSquare(right.z)
    let u1        = p256FieldMultiply(left.x, z2Squared)
    let u2        = p256FieldMultiply(right.x, z1Squared)
    let s1        = p256FieldMultiply(left.y, p256FieldMultiply(right.z, z2Squared))
    let s2        = p256FieldMultiply(right.y, p256FieldMultiply(left.z, z1Squared))
    let zProduct  = p256FieldMultiply(left.z, right.z)
    return p256FinishPointAdd(left, right, doubled, u1, u2, s1, s2, zProduct)
}

private func p256PointAddAffine(left, right, doubled: P256Point)->P256Point
{
    // Generator table points have Montgomery Z = 1. A zero selection is
    // still recognized by the complete addition's masked infinity handling.
    let zSquared = p256FieldSquare(left.z)
    let u2       = p256FieldMultiply(right.x, zSquared)
    let zCubed   = p256FieldMultiply(left.z, zSquared)
    let s2       = p256FieldMultiply(right.y, zCubed)
    return p256FinishPointAdd(left, right, doubled, left.x, u2, left.y, s2, left.z)
}

#[Swag.Inline]
private func p256FinishPointAdd(left, right, doubled: P256Point, u1, u2, s1, s2, zProduct: P256Field)->P256Point
{
    let h        = p256FieldSubtract(u2, u1)
    let r        = p256FieldSubtract(s2, s1)
    let hSquared = p256FieldSquare(h)
    let hCubed   = p256FieldMultiply(h, hSquared)
    let u1h2     = p256FieldMultiply(u1, hSquared)
    let x3       = p256FieldSubtract(p256FieldSubtract(p256FieldSquare(r), hCubed), p256FieldDouble(u1h2))
    let y3       = p256FieldSubtract(p256FieldMultiply(r, p256FieldSubtract(u1h2, x3)), p256FieldMultiply(s1, hCubed))
    let z3       = p256FieldMultiply(h, zProduct)
    var sum: P256Point
    sum.x = x3
    sum.y = y3
    sum.z = z3

    let infinity = p256Infinity()
    let sameX    = cast(u32, p256FieldEqual(u1, u2))
    let sameY    = cast(u32, p256FieldEqual(s1, s2))
    var result   = p256PointSelect(sum, doubled, (sameX & sameY) != 0)
    result = p256PointSelect(result, infinity, (sameX & (sameY ^ 1)) != 0)
    result = p256PointSelect(result, right, p256FieldEqual(left.z, P256Field{}))
    result = p256PointSelect(result, left, p256FieldEqual(right.z, P256Field{}))
    return result
}

private func p256ScalarMultiply(scalar: const *P256Field, point: P256Point)->P256Point
{
    // The table depends only on the input point. Each window scans every entry.
    var multiples: [16] P256Point
    multiples[1] = point
    let doubledPoint = p256PointDouble(point)
    for index in 2 until multiples.count do
        multiples[index] = p256PointAdd(point, multiples[index - 1], doubledPoint)

    var result = p256Infinity()
    for window in 64
    {
        for 4 do
            result = p256PointDouble(result)

        let nibbleIndex = 63 - window
        let nibble      = (scalar[].limbs[nibbleIndex / 8] >> ((nibbleIndex % 8) * 4)) & 15
        var selected    = p256Infinity()
        for index in 1 until multiples.count do
            selected = p256PointSelect(selected, multiples[index], index == nibble)

        var doubled = p256PointDouble(result)
        result = p256PointAdd(result, selected, doubled)
        Crypto.secureClear(Swag.makeSlice(&selected, 1))
        Crypto.secureClear(Swag.makeSlice(&doubled, 1))
    }

    return result
}

private struct P256AffinePoint
{
    x: P256Field
    y: P256Field
}

// Entry d-1 is the Montgomery representation of the sum of [2^(64*j)]G
// for each set bit j in d. The zero entry is the point at infinity.
private const P256GeneratorComb: [15] P256AffinePoint = [
    {P256Field{limbs: [0x18A9143C, 0x79E730D4, 0x5FEDB601, 0x75BA95FC, 0x77622510, 0x79FB732B, 0xA53755C6, 0x18905F76]},
     P256Field{limbs: [0xCE95560A, 0xDDF25357, 0xBA19E45C, 0x8B4AB8E4, 0xDD21F325, 0xD2E88688, 0x25885D85, 0x8571FF18]}},
    {P256Field{limbs: [0x16A0D2BB, 0x4F922FC5, 0x1A623499, 0x0D5CC16C, 0x57C62C8B, 0x9241CF3A, 0xFD1B667F, 0x2F5E6961]},
     P256Field{limbs: [0xF5A01797, 0x5C15C70B, 0x60956192, 0x3D20B44D, 0x071FDB52, 0x04911B37, 0x8D6F0F7B, 0xF648F916]}},
    {P256Field{limbs: [0xE137BBBC, 0x9E566847, 0x8A6A0BEC, 0xE434469E, 0x79D73463, 0xB1C42761, 0x133D0015, 0x5ABE0285]},
     P256Field{limbs: [0xC04C7DAB, 0x92AA837C, 0x43260C07, 0x573D9F4C, 0x78E6CC37, 0x0C931562, 0x6B6F7383, 0x94BB725B]}},
    {P256Field{limbs: [0xBFE20925, 0x62A8C244, 0x8FDCE867, 0x91C19AC3, 0xDD387063, 0x5A96A5D5, 0x21D324F6, 0x61D587D4]},
     P256Field{limbs: [0xA37173EA, 0xE87673A2, 0x53778B65, 0x23848008, 0x05BAB43E, 0x10F8441E, 0x4621EFBE, 0xFA11FE12]}},
    {P256Field{limbs: [0x2CB19FFD, 0x1C891F2B, 0xB1923C23, 0x01BA8D5B, 0x8AC5CA8E, 0xB6D03D67, 0x1F13BEDC, 0x586EB04C]},
     P256Field{limbs: [0x27E8ED09, 0x0C35C6E5, 0x1819EDE2, 0x1E81A33C, 0x56C652FA, 0x278FD6C0, 0x70864F11, 0x19D5AC08]}},
    {P256Field{limbs: [0xD2B533D5, 0x62577734, 0xA1BDDDC0, 0x673B8AF6, 0xA79EC293, 0x577E7C9A, 0xC3B266B1, 0xBB6DE651]},
     P256Field{limbs: [0xB65259B3, 0xE7E9303A, 0xD03A7480, 0xD6A0AFD3, 0x9B3CFC27, 0xC5AC83D1, 0x5D18B99B, 0x60B4619A]}},
    {P256Field{limbs: [0x1AE5AA1C, 0xBD6A38E1, 0x49E73658, 0xB8B7652B, 0xEE5F87ED, 0x0B130014, 0xAEEBFFCD, 0x9D0F27B2]},
     P256Field{limbs: [0x7A730A55, 0xCA924631, 0xDDBBC83A, 0x9C955B2F, 0xAC019A71, 0x07C1DFE0, 0x356EC48D, 0x244A566D]}},
    {P256Field{limbs: [0xF4F8B16A, 0x56F8410E, 0xC47B266A, 0x97241AFE, 0x6D9C87C1, 0x0A406B8E, 0xCD42AB1B, 0x803F3E02]},
     P256Field{limbs: [0x04DBEC69, 0x7F0309A8, 0x3BBAD05F, 0xA83B85F7, 0xAD8E197F, 0xC6097273, 0x5067ADC1, 0xC097440E]}},
    {P256Field{limbs: [0xC379AB34, 0x846A56F2, 0x841DF8D1, 0xA8EE068B, 0x176C68EF, 0x20314459, 0x915F1F30, 0xF1AF32D5]},
     P256Field{limbs: [0x5D75BD50, 0x99C37531, 0xF72F67BC, 0x837CFFBA, 0x48D7723F, 0x0613A418, 0xE2D41C8B, 0x23D0F130]}},
    {P256Field{limbs: [0xD5BE5A2B, 0xED93E225, 0x5934F3C6, 0x6FE79983, 0x22626FFC, 0x43140926, 0x7990216A, 0x50BBB4D9]},
     P256Field{limbs: [0xE57EC63E, 0x378191C6, 0x181DCDB2, 0x65422C40, 0x0236E0F6, 0x41A8099B, 0x01FE49C3, 0x2B100118]}},
    {P256Field{limbs: [0x9B391593, 0xFC68B5C5, 0x598270FC, 0xC385F5A2, 0xD19ADCBB, 0x7144F3AA, 0x83FBAE0C, 0xDD558999]},
     P256Field{limbs: [0x74B82FF4, 0x93B88B8E, 0x71E734C9, 0xD2E03C40, 0x43C0322A, 0x9A7A9EAF, 0x149D6041, 0xE6E4C551]}},
    {P256Field{limbs: [0x80EC21FE, 0x5FE14BFE, 0xC255BE82, 0xF6CE116A, 0x2F4A5D67, 0x98BC5A07, 0xDB7E63AF, 0xFAD27148]},
     P256Field{limbs: [0x29AB05B3, 0x90C0B6AC, 0x4E251AE6, 0x37A9A83C, 0xC2AADE7D, 0x0A7DC875, 0x9F0E1A84, 0x77387DE3]}},
    {P256Field{limbs: [0xA56C0DD7, 0x1E9ECC49, 0x46086C74, 0xA5CFFCD8, 0xF505AECE, 0x8F7A1408, 0xBEF0C47E, 0xB37B85C0]},
     P256Field{limbs: [0xCC0E6A8F, 0x3596B6E4, 0x6B388F23, 0xFD6D4BBF, 0xC39CEF4E, 0xABA453FA, 0xF9F628D5, 0x9C135AC8]}},
    {P256Field{limbs: [0x95C8F8BE, 0x0A1C7294, 0x3BF362BF, 0x2961C480, 0xDF63D4AC, 0x9E418403, 0x91ECE900, 0xC109F9CB]},
     P256Field{limbs: [0x58945705, 0xC2D095D0, 0xDDEB85C0, 0xB9083D96, 0x7A40449B, 0x84692B8D, 0x2EEE1EE1, 0x9BC3344F]}},
    {P256Field{limbs: [0x42913074, 0x0D5AE356, 0x48A542B1, 0x55491B27, 0xB310732A, 0x469CA665, 0x5F1A4CC1, 0x29591D52]},
     P256Field{limbs: [0xB84F983F, 0xE76F5B6B, 0x9F5F84E1, 0xBE7EEF41, 0x80BAA189, 0x1200D496, 0x18EF332C, 0x6376551F]}}]

private func p256MultiplyGenerator(scalar: const *P256Field)->P256Point
{
    let one    = P256Field{limbs: P256MontgomeryOne}
    var result = p256Infinity()
    for step in 64
    {
        result = p256PointDouble(result)
        let bitIndex  = 63 - step
        let wordIndex = bitIndex / 32
        let shift     = bitIndex % 32
        let digits0   = (scalar[].limbs[wordIndex] >> shift) & 1
        let digits1   = (scalar[].limbs[wordIndex + 2] >> shift) & 1
        let digits2   = (scalar[].limbs[wordIndex + 4] >> shift) & 1
        let digits3   = (scalar[].limbs[wordIndex + 6] >> shift) & 1
        let digit     = digits0 | (digits1 << 1) | (digits2 << 2) | (digits3 << 3)

        var selection: P256Point
        for index in P256GeneratorComb.count
        {
            let matched = index + 1 == digit
            let point   = P256GeneratorComb[index]
            selection.x = p256FieldSelect(selection.x, point.x, matched)
            selection.y = p256FieldSelect(selection.y, point.y, matched)
        }

        selection.z = p256FieldSelect(P256Field{}, one, digit != 0)

        var doubled = p256PointDouble(result)
        result = p256PointAddAffine(result, selection, doubled)
        Crypto.secureClear(Swag.makeSlice(&selection, 1))
        Crypto.secureClear(Swag.makeSlice(&doubled, 1))
    }

    return result
}

private func p256ValidatePublicPoint(point: P256Point)->bool
{
    let xSquared  = p256FieldSquare(point.x)
    let xCubed    = p256FieldMultiply(xSquared, point.x)
    let ySquared  = p256FieldSquare(point.y)
    let threeX    = p256FieldTriple(point.x)
    let curveBRaw = P256Field{limbs: [0x27D2604B, 0x3BCE3C3E, 0xCC53B0F6, 0x651D06B0,
                                      0x769886BC, 0xB3EBBD55, 0xAA3A93E7, 0x5AC635D8]}
    let curveB   = p256ToMontgomery(curveBRaw)
    let expected = p256FieldAdd(p256FieldSubtract(xCubed, threeX), curveB)
    return p256FieldEqual(ySquared, expected)
}

private func p256AffineX(point: P256Point)->P256Field
{
    var inverse = p256FieldInverse(point.z)
    let result  = p256FieldMultiply(point.x, p256FieldSquare(inverse))
    Crypto.secureClear(Swag.makeSlice(&inverse, 1))
    return result
}

// Derives the uncompressed P-256 public key for a 32-byte private scalar.
//
// The scalar must be in the range 1 through the curve order minus one; `publicKey` must hold
// exactly 65 bytes and receives the SEC1 0x04 || X || Y encoding.
func p256PublicKey(privateKey: const [..] u8, publicKey: [..] u8) fail
{
    if publicKey.count != P256PublicKeySize do
        fail Errors.BadParameterError{"P-256 public key output must be 65 bytes"}
    var scalar = try p256ScalarDecode(privateKey)
    defer Crypto.secureClear(Swag.makeSlice(&scalar, 1))
    var point = p256MultiplyGenerator(&scalar)
    defer Crypto.secureClear(Swag.makeSlice(&point, 1))

    var inverse = p256FieldInverse(point.z)
    defer Crypto.secureClear(Swag.makeSlice(&inverse, 1))
    var inverseSquared = p256FieldSquare(inverse)
    defer Crypto.secureClear(Swag.makeSlice(&inverseSquared, 1))

    publicKey[0] = 4
    p256FieldEncode(p256FieldMultiply(point.x, inverseSquared), publicKey[1 until 33])
    p256FieldEncode(p256FieldMultiply(point.y, p256FieldMultiply(inverseSquared, inverse)),
                    publicKey[33 until 65])
}

// Derives a 32-byte P-256 ECDH shared secret from a private scalar and an uncompressed peer key.
//
// The peer key must use SEC1 0x04 || X || Y encoding and identify a point on P-256. Invalid key
// sizes, encodings, coordinates, or private scalars fail with [[Core.Errors.BadParameterError]].
func p256Ecdh(privateKey, peerPublicKey: const [..] u8, sharedSecret: [..] u8) fail
{
    if peerPublicKey.count != P256PublicKeySize or
       sharedSecret.count != P256ScalarSize or
       peerPublicKey[0] != 4 do
        fail Errors.BadParameterError{"P-256 ECDH needs a 65-byte uncompressed peer key and a 32-byte output"}

    var scalar = try p256ScalarDecode(privateKey)
    defer Crypto.secureClear(Swag.makeSlice(&scalar, 1))
    var peer: P256Point
    peer.x       = try p256FieldDecode(peerPublicKey[1 until 33])
    peer.y       = try p256FieldDecode(peerPublicKey[33 until 65])
    peer.z.limbs = P256MontgomeryOne
    if not p256ValidatePublicPoint(peer) do
        fail Errors.BadParameterError{"P-256 peer public key is not on the curve"}

    var shared = p256ScalarMultiply(&scalar, peer)
    defer Crypto.secureClear(Swag.makeSlice(&shared, 1))
    if p256FieldEqual(shared.z, P256Field{}) do
        fail Errors.BadParameterError{"P-256 ECDH produced the point at infinity"}
    p256FieldEncode(p256AffineX(shared), sharedSecret)
}

// Signs `message` with deterministic ECDSA using SHA-256 and a P-256 private scalar.
//
// `signature` must hold 64 bytes and receives the fixed-width, big-endian `r || s` encoding.
// The private scalar must be in the range 1 through the curve order minus one.
func p256EcdsaSign(privateKey, message: const [..] u8, signature: [..] u8) fail
{
    if signature.count != 64 do
        fail Errors.BadParameterError{"P-256 ECDSA signature output must be 64 bytes"}
    var privateScalar = try p256ScalarDecode(privateKey)
    defer Crypto.secureClear(Swag.makeSlice(&privateScalar, 1))
    var messageDigest = p256DigestBytes(Hash.Sha256.compute(message))
    defer Crypto.secureClear(Swag.makeSlice(&messageDigest, 1))
    var nonceBytes = try p256Rfc6979Nonce(privateScalar, messageDigest)
    defer Crypto.secureClear(Swag.makeSlice(&nonceBytes, 1))
    var nonce = try p256ScalarDecode(nonceBytes)
    defer Crypto.secureClear(Swag.makeSlice(&nonce, 1))

    var noncePoint = p256MultiplyGenerator(&nonce)
    defer Crypto.secureClear(Swag.makeSlice(&noncePoint, 1))
    var r = p256OrderReduce(p256FromMontgomery(p256AffineX(noncePoint)))
    if not p256ScalarIsValid(r) do
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid nonce"}

    let zRaw = P256Field{limbs: [
        (cast(u32, messageDigest[28]) << 24) | (cast(u32, messageDigest[29]) << 16) |
        (cast(u32, messageDigest[30]) << 8) | cast(u32, messageDigest[31]),
        (cast(u32, messageDigest[24]) << 24) | (cast(u32, messageDigest[25]) << 16) |
        (cast(u32, messageDigest[26]) << 8) | cast(u32, messageDigest[27]),
        (cast(u32, messageDigest[20]) << 24) | (cast(u32, messageDigest[21]) << 16) |
        (cast(u32, messageDigest[22]) << 8) | cast(u32, messageDigest[23]),
        (cast(u32, messageDigest[16]) << 24) | (cast(u32, messageDigest[17]) << 16) |
        (cast(u32, messageDigest[18]) << 8) | cast(u32, messageDigest[19]),
        (cast(u32, messageDigest[12]) << 24) | (cast(u32, messageDigest[13]) << 16) |
        (cast(u32, messageDigest[14]) << 8) | cast(u32, messageDigest[15]),
        (cast(u32, messageDigest[8]) << 24) | (cast(u32, messageDigest[9]) << 16) |
        (cast(u32, messageDigest[10]) << 8) | cast(u32, messageDigest[11]),
        (cast(u32, messageDigest[4]) << 24) | (cast(u32, messageDigest[5]) << 16) |
        (cast(u32, messageDigest[6]) << 8) | cast(u32, messageDigest[7]),
        (cast(u32, messageDigest[0]) << 24) | (cast(u32, messageDigest[1]) << 16) |
        (cast(u32, messageDigest[2]) << 8) | cast(u32, messageDigest[3])]}
    var z = p256OrderReduce(zRaw)
    defer Crypto.secureClear(Swag.makeSlice(&z, 1))

    var nonceMontgomery = p256OrderToMontgomery(nonce)
    defer Crypto.secureClear(Swag.makeSlice(&nonceMontgomery, 1))
    var rMontgomery = p256OrderToMontgomery(r)
    defer Crypto.secureClear(Swag.makeSlice(&rMontgomery, 1))
    var privateMontgomery = p256OrderToMontgomery(privateScalar)
    defer Crypto.secureClear(Swag.makeSlice(&privateMontgomery, 1))
    var zMontgomery = p256OrderToMontgomery(z)
    defer Crypto.secureClear(Swag.makeSlice(&zMontgomery, 1))

    var inverseNonce = p256OrderPower(nonceMontgomery, P256OrderInverseExponent)
    defer Crypto.secureClear(Swag.makeSlice(&inverseNonce, 1))
    var rd = p256OrderMultiply(rMontgomery, privateMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&rd, 1))
    var sum = p256OrderAdd(zMontgomery, rd)
    defer Crypto.secureClear(Swag.makeSlice(&sum, 1))
    var sMontgomery = p256OrderMultiply(inverseNonce, sum)
    defer Crypto.secureClear(Swag.makeSlice(&sMontgomery, 1))
    var s = p256OrderFromMontgomery(sMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&s, 1))
    if not p256ScalarIsValid(s) do
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid signature"}

    p256OrderEncode(r, signature[until 32])
    p256OrderEncode(s, signature[32 to])
    Crypto.secureClear(Swag.makeSlice(&r, 1))
}

// Verifies a fixed-width P-256 ECDSA signature over `message` using SHA-256.
//
// The public key must use SEC1 0x04 || X || Y encoding. Invalid public keys fail with
// [[Core.Errors.BadParameterError]]; a malformed or incorrect signature returns false.
func p256EcdsaVerify(publicKey, message, signature: const [..] u8)->bool fail
{
    if publicKey.count != P256PublicKeySize or publicKey[0] != 4 or signature.count != 64 do
        fail Errors.BadParameterError{"P-256 ECDSA needs a 65-byte uncompressed key and a 64-byte signature"}

    var publicPoint: P256Point
    publicPoint.x       = try p256FieldDecode(publicKey[1 until 33])
    publicPoint.y       = try p256FieldDecode(publicKey[33 until 65])
    publicPoint.z.limbs = P256MontgomeryOne
    if not p256ValidatePublicPoint(publicPoint) do
        fail Errors.BadParameterError{"P-256 ECDSA public key is not on the curve"}
    defer Crypto.secureClear(Swag.makeSlice(&publicPoint, 1))

    var rBytes: [32] u8
    var sBytes: [32] u8
    Swag.memcpy(&rBytes[0], signature.buffer, 32)
    Swag.memcpy(&sBytes[0], signature.buffer + 32, 32)
    var r = p256ReadInteger(rBytes)
    var s = p256ReadInteger(sBytes)
    Crypto.secureClear(Swag.makeSlice(&rBytes, 1))
    Crypto.secureClear(Swag.makeSlice(&sBytes, 1))
    if not p256ScalarIsValid(r) or not p256ScalarIsValid(s)
    {
        Crypto.secureClear(Swag.makeSlice(&r, 1))
        Crypto.secureClear(Swag.makeSlice(&s, 1))
        return false
    }

    var messageDigest = p256DigestBytes(Hash.Sha256.compute(message))
    defer Crypto.secureClear(Swag.makeSlice(&messageDigest, 1))
    let zRaw = P256Field{limbs: [
        (cast(u32, messageDigest[28]) << 24) | (cast(u32, messageDigest[29]) << 16) |
        (cast(u32, messageDigest[30]) << 8) | cast(u32, messageDigest[31]),
        (cast(u32, messageDigest[24]) << 24) | (cast(u32, messageDigest[25]) << 16) |
        (cast(u32, messageDigest[26]) << 8) | cast(u32, messageDigest[27]),
        (cast(u32, messageDigest[20]) << 24) | (cast(u32, messageDigest[21]) << 16) |
        (cast(u32, messageDigest[22]) << 8) | cast(u32, messageDigest[23]),
        (cast(u32, messageDigest[16]) << 24) | (cast(u32, messageDigest[17]) << 16) |
        (cast(u32, messageDigest[18]) << 8) | cast(u32, messageDigest[19]),
        (cast(u32, messageDigest[12]) << 24) | (cast(u32, messageDigest[13]) << 16) |
        (cast(u32, messageDigest[14]) << 8) | cast(u32, messageDigest[15]),
        (cast(u32, messageDigest[8]) << 24) | (cast(u32, messageDigest[9]) << 16) |
        (cast(u32, messageDigest[10]) << 8) | cast(u32, messageDigest[11]),
        (cast(u32, messageDigest[4]) << 24) | (cast(u32, messageDigest[5]) << 16) |
        (cast(u32, messageDigest[6]) << 8) | cast(u32, messageDigest[7]),
        (cast(u32, messageDigest[0]) << 24) | (cast(u32, messageDigest[1]) << 16) |
        (cast(u32, messageDigest[2]) << 8) | cast(u32, messageDigest[3])]}
    var z = p256OrderReduce(zRaw)
    defer Crypto.secureClear(Swag.makeSlice(&z, 1))
    var rMontgomery = p256OrderToMontgomery(r)
    defer Crypto.secureClear(Swag.makeSlice(&rMontgomery, 1))
    var sMontgomery = p256OrderToMontgomery(s)
    defer Crypto.secureClear(Swag.makeSlice(&sMontgomery, 1))
    var inverseS = p256OrderPower(sMontgomery, P256OrderInverseExponent)
    defer Crypto.secureClear(Swag.makeSlice(&inverseS, 1))
    var zMontgomery = p256OrderToMontgomery(z)
    defer Crypto.secureClear(Swag.makeSlice(&zMontgomery, 1))
    var u1Montgomery = p256OrderMultiply(zMontgomery, inverseS)
    defer Crypto.secureClear(Swag.makeSlice(&u1Montgomery, 1))
    var u2Montgomery = p256OrderMultiply(rMontgomery, inverseS)
    defer Crypto.secureClear(Swag.makeSlice(&u2Montgomery, 1))
    var u1 = p256OrderFromMontgomery(u1Montgomery)
    defer Crypto.secureClear(Swag.makeSlice(&u1, 1))
    var u2 = p256OrderFromMontgomery(u2Montgomery)
    defer Crypto.secureClear(Swag.makeSlice(&u2, 1))

    var first = p256MultiplyGenerator(&u1)
    defer Crypto.secureClear(Swag.makeSlice(&first, 1))
    var second = p256ScalarMultiply(&u2, publicPoint)
    defer Crypto.secureClear(Swag.makeSlice(&second, 1))
    var sum = p256PointAdd(first, second, p256PointDouble(first))
    defer Crypto.secureClear(Swag.makeSlice(&sum, 1))
    if p256FieldEqual(sum.z, P256Field{})
    {
        Crypto.secureClear(Swag.makeSlice(&r, 1))
        Crypto.secureClear(Swag.makeSlice(&s, 1))
        return false
    }

    var x = p256OrderReduce(p256FromMontgomery(p256AffineX(sum)))
    defer Crypto.secureClear(Swag.makeSlice(&x, 1))
    Crypto.secureClear(Swag.makeSlice(&s, 1))
    let valid = p256FieldEqual(x, r)
    Crypto.secureClear(Swag.makeSlice(&r, 1))
    return valid
}

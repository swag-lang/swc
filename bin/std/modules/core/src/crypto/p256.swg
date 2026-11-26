#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// P-256 private scalar and coordinate size in bytes.
public const P256ScalarSize = 32

// P-256 uncompressed public key size in bytes, including the 0x04 prefix.
public const P256PublicKeySize = 65

private struct P256Field
{
    limbs: [4] u64
}

private struct P256Point
{
    x: P256Field
    y: P256Field
    z: P256Field
}

private const P256Modulus: [4] u64 = [
    0xFFFFFFFFFFFFFFFF, 0x00000000FFFFFFFF, 0x0000000000000000, 0xFFFFFFFF00000001]

private const P256Order: [4] u64 = [
    0xF3B9CAC2FC632551, 0xBCE6FAADA7179E84, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF00000000]

private const P256ModulusMinusOrder: [4] u64 = [
    0x0C46353D039CDAAE, 0x4319055358E8617B, 0x0000000000000000, 0x0000000000000000]
private const P256MontgomeryOne: [4] u64 = [
    0x0000000000000001, 0xFFFFFFFF00000000, 0xFFFFFFFFFFFFFFFF, 0x00000000FFFFFFFE]

private const P256MontgomeryR2: [4] u64 = [
    0x0000000000000003, 0xFFFFFFFBFFFFFFFF, 0xFFFFFFFFFFFFFFFE, 0x00000004FFFFFFFD]

private const P256OrderMontgomeryR2: [4] u64 = [
    0x83244C95BE79EEA2, 0x4699799C49BD6FA6, 0x2845B2392B6BEC59, 0x66E12D94F3D95620]

private const P256OrderInverseExponent: [4] u64 = [
    0xF3B9CAC2FC63254F, 0xBCE6FAADA7179E84, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF00000000]

private const P256OrderWordInverse = 0xCCD1C8AAEE00BC4F'u64

#[Swag.Inline]
private func p256MultiplyAdd(left, right, addend, carry: u64)->{word: u64, carry: u64}
{
    var high: u64
    let word = Swag.mulWide(left, right, addend, carry, &high)
    return {word, high}
}

private func(IsField: bool) p256MontgomeryMultiply(left, right: [4] u64)->[4] u64
{
    const Modulus = IsField ? P256Modulus : P256Order
    var temporary: [5] u64
    for multiplier in right
    {
        var carry = 0_u64
        for word in 8
        {
            let product = p256MultiplyAdd(left[word], multiplier, temporary[word], carry)
            temporary[word] = product.word
            carry = product.carry
        }

        let productTop   = temporary[4] + carry
        let productCarry = cast(u64, productTop < carry)
        #static if IsField
        {
            let product = cast(u64, reduction) * modulus[word] + temporary[word] + carry
            if word
            {
                temporary[word - 1] = cast(u32, product)
            }

            carry = product >> 32
        }

        // Retain the carry from both top-word additions before shifting off word zero.
        let top = productTop + carry
        temporary[3] = top
        temporary[4] = productCarry + cast(u64, top < carry)
    }

    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let word = temporary[index] - Modulus[index]
        difference[index] = word - borrow
        borrow = cast(u64, temporary[index] < Modulus[index]) | cast(u64, word < borrow)
    }

    let useDifference = cast(u32, (temporary[8] != 0) or (borrow == 0))
    let mask = 0_u32 - useDifference
    var result: #returntype
    for index in 8
    {
        result[index] = (difference[index] & mask) | (temporary[index] & ~mask)
    }

    Crypto.secureClear(temporary)
    Crypto.secureClear(difference)
    return result
}

private func p256ToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'true(value.limbs, P256MontgomeryR2)
    return result
}

private func p256FromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'true(value.limbs, [1, 0, 0, 0])
    return result
}

#[Swag.Inline]
private func p256AddWord(left, right, carry: u64)->{word: u64, carry: u64}
{
    var sum: [8] u32
    var carry = 0_u64
    for index in 8
    {
        let word = cast(u64, left.limbs[index]) + right.limbs[index] + carry
        sum[index] = cast(u32, word)
        carry      = word >> 32
    }

    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Modulus[index]) + borrow
        let word       = cast(u64, sum[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let useDifference = cast(u32, (carry != 0) or (borrow == 0))
    let mask = 0_u32 - useDifference
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (difference[index] & mask) | (sum[index] & ~mask)
    }

    return result
}

#[Swag.Inline]
private func p256SubtractWord(left, right, borrow: u64)->{word: u64, borrow: u64}
{
    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let difference = p256SubtractWord(value.limbs[index], modulus[index], borrow)
        reduced.limbs[index] = difference.word
        borrow = difference.borrow
    }

    var corrected: [8] u32
    var carry = 0_u64
    for index in 8
    {
        let sum = p256AddWord(left.limbs[index], right.limbs[index], carry)
        result.limbs[index] = sum.word
        carry = sum.carry
    }

    return p256Reduce(result, modulus, carry)
}

private func p256SubtractMod(left, right: P256Field, modulus: [4] u64)->P256Field
{
    var result: P256Field
    var borrow = 0'u64
    for index in 4
    {
        let difference = p256SubtractWord(left.limbs[index], right.limbs[index], borrow)
        result.limbs[index] = difference.word
        borrow = difference.borrow
    }

    let mask  = 0'u64 - borrow
    var carry = 0'u64
    for index in 4
    {
        let sum = p256AddWord(result.limbs[index], modulus[index] & mask, carry)
        result.limbs[index] = sum.word
        carry = sum.carry
    }

    let mask = 0_u32 - cast(u32, borrow)
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (corrected[index] & mask) | (difference[index] & ~mask)
    }

    return result
}

private func p256FieldAdd(left, right: P256Field)->P256Field => p256AddMod(left, right, P256Modulus)

private func p256FieldSubtract(left, right: P256Field)->P256Field => p256SubtractMod(left, right, P256Modulus)

private func p256FieldMultiply(left, right: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'true(left.limbs, right.limbs)
    return result
}

private func p256FieldSquare(value: P256Field)->P256Field => p256FieldMultiply(value, value)

private func p256FieldSmall(value: P256Field, factor: u32)->P256Field
{
    var result: P256Field
    var iteration = 0_u32
    while iteration < factor
    {
        result    = p256FieldAdd(result, value)
        iteration += 1
    }

private func p256FieldTriple(value: P256Field)->P256Field => p256FieldAdd(p256FieldDouble(value), value)

private func p256FieldEqual(left, right: P256Field)->bool
{
    var difference = 0_u32
    for index in 8
    {
        difference |= left.limbs[index] ^ right.limbs[index]
    }

    return difference == 0
}

private func p256FieldSelect(left, right: P256Field, selectRight: bool)->P256Field
{
    let mask = 0_u32 - cast(u32, selectRight)
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (right.limbs[index] & mask) | (left.limbs[index] & ~mask)
    }

    return result
}

private func p256FieldSquareRepeated(value: P256Field, count: u32)->P256Field
{
    var result = value
    for count do
        result = p256FieldSquare(result)
        if (exponent[bit / 32] >> (bit % 32)) & 1
        {
            result = p256FieldMultiply(result, value)
        }
    }

    return result
}

private func p256FieldInverse(value: P256Field)->P256Field
{
    var sum: [8] u32
    var carry = 0_u64
    for index in 8
    {
        let word = cast(u64, left.limbs[index]) + right.limbs[index] + carry
        sum[index] = cast(u32, word)
        carry      = word >> 32
    }

    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, sum[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let mask = 0_u32 - cast(u32, (carry != 0) or (borrow == 0))
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (difference[index] & mask) | (sum[index] & ~mask)
    }

    return result
}

private func p256OrderSubtract(left, right: P256Field)->P256Field
{
    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let subtrahend = cast(u64, right.limbs[index]) + borrow
        let word       = cast(u64, left.limbs[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    var corrected: [8] u32
    var carry = 0_u64
    for index in 8
    {
        let word = cast(u64, difference[index]) + P256Order[index] + carry
        corrected[index] = cast(u32, word)
        carry = word >> 32
    }

    let mask = 0_u32 - cast(u32, borrow)
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (corrected[index] & mask) | (difference[index] & ~mask)
    }

    return result
}

private func p256OrderMultiply(left, right: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'false(left.limbs, right.limbs)
    return result
}

private func p256OrderToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'false(value.limbs, P256OrderMontgomeryR2)
    return result
}

private func p256OrderFromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply'false(value.limbs, [1, 0, 0, 0])
    return result
}

private func p256OrderInverse(value: P256Field)->P256Field
{
    var powers: [16] P256Field
    powers[1] = value
    for index in 2 until powers.count do
        powers[index] = p256OrderMultiply(powers[index - 1], value)

    // Every table index comes from the public exponent n - 2.
    var result = powers[P256OrderInverseExponent[3] >> 60]
    for window in 63
    {
        let bit = 255 - step
        result = p256OrderMultiply(result, result)
        if (exponent[bit / 32] >> (bit % 32)) & 1
        {
            result = p256OrderMultiply(result, value)
        }
    }

    Crypto.secureClear(powers)
    return result
}

private func p256OrderReduce(value: P256Field)->P256Field => p256Reduce(value, P256Order, 0)

private func p256WriteInteger(value: P256Field, destination: [..] u8)
{
    let words = cast([*] u64, destination.buffer)
    for index in 4 do
        words[3 - index] = Math.nativeToBigEndian(value.limbs[index])
}

private func p256LessThan(value: P256Field, bound: [4] u64)->bool
{
    var difference: [8] u32
    var borrow = 0_u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, value.limbs[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let mask = 0_u32 - cast(u32, borrow == 0)
    var result: #returntype
    for index in 8
    {
        result.limbs[index] = (difference[index] & mask) | (value.limbs[index] & ~mask)
    }

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
    var borrow  = 0_u64
    var nonZero = 0_u32
    for word in value.limbs
    {
        nonZero |= word
    }

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
        for byte in 4
        {
            result[index * 4 + byte] = Math.byteAt(digest[index], 3 - byte)
        }
    }

    return result
}

internal func p256Rfc6979Nonce(privateKey: const [..] u8, digest: [32] u8)->[32] u8
{
    var key:   [32] u8
    var value: [32] u8
    Memory.set(&value[0], 1_u8, value.count)
    var scalarBytes: [32] u8
    p256OrderEncode(privateScalar, scalarBytes)

    var input: Array!{u8}
    input.add(value)
    input.add(0_u8)
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
    input.add(1_u8)
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
        value = HmacSha256.compute(key, value)
        var candidate = p256ReadInteger(value)
        let valid     = p256ScalarIsValid(candidate)
        Crypto.secureClear(Swag.makeSlice(&candidate, 1))
        if valid
        {
            let result = value
            return result
        }

        Crypto.secureClear(Swag.makeSlice(&candidate, 1))

        input.resize(0)
        input.add(value)
        input.add(0_u8)
        key = HmacSha256.compute(key, input.toSlice())
        Crypto.secureClear(input.toSlice())
        input.resize(0)
        input.add(value)
        value = HmacSha256.compute(key, input.toSlice())
        Crypto.secureClear(input.toSlice())
    }
}

private func p256ReadInteger(bytes: const [..] u8)->P256Field
{
    let words = cast(const [*] u64, bytes.buffer)
    var result: P256Field
    for index in 4 do
        result.limbs[index] = Math.bigEndianToNative(words[3 - index])
    return result
}

private func p256FieldDecode(bytes: const [..] u8)->P256Field fail
{
    if bytes.count != P256ScalarSize
    {
        fail Errors.BadParameterError{"P-256 coordinates and scalars must be 32 bytes"}
    }

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
    var index = 8_u32
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

    if not lessThanModulus
    {
        fail Errors.BadParameterError{"P-256 coordinate must be smaller than the field modulus"}
    }

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
    if bytes.count != P256ScalarSize
    {
        fail Errors.BadParameterError{"P-256 private scalar must be 32 bytes"}
    }

    var result: #returntype
    for index in 8
    {
        let offset = bytes.count - (cast(u64, index + 1) * 4)
        result.limbs[index] = (cast(u32, bytes[offset]) << 24) |
                              (cast(u32, bytes[offset + 1]) << 16) |
                              (cast(u32, bytes[offset + 2]) << 8) |
                              cast(u32, bytes[offset + 3])
    }

    var borrow = 0_u64
    for index in 8
    {
        let subtrahend = cast(u64, P256Order[index]) + borrow
        let word       = cast(u64, result.limbs[index]) - subtrahend
        borrow = word >> 63
    }

    var nonZero = 0_u32
    for word in result.limbs
    {
        nonZero |= word
    }

    if borrow == 0 or not nonZero
    {
        fail Errors.BadParameterError{"P-256 private scalar must be between 1 and the curve order minus one"}
    }

    return result
}

private func p256FieldEncode(value: P256Field, destination: [..] u8)
{
    var ordinary = p256FromMontgomery(value)
    p256WriteInteger(ordinary, destination)
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

private struct P256AffinePoint
{
    let mask = 0_u32 - swap
    for index in 8
    {
        var difference = (left[].x.limbs[index] ^ right[].x.limbs[index]) & mask
        left[].x.limbs[index]  ^= difference
        right[].x.limbs[index] ^= difference
        difference             = (left[].y.limbs[index] ^ right[].y.limbs[index]) & mask
        left[].y.limbs[index]  ^= difference
        right[].y.limbs[index] ^= difference
        difference             = (left[].z.limbs[index] ^ right[].z.limbs[index]) & mask
        left[].z.limbs[index]  ^= difference
        right[].z.limbs[index] ^= difference
    }
}

private func p256ScalarMultiply(scalar: const *P256Field, point: P256Point)->P256Point
{
    // The decoded peer key has affine coordinates. Table construction
    // uses only that point and every scalar window scans the whole table.
    let one      = P256Field{limbs: P256MontgomeryOne}
    let identity = P256HomogeneousPoint{y: one}
    let affine   = P256AffinePoint{x: point.x, y: point.y}
    var multiples: [16] P256HomogeneousPoint
    multiples[1] = P256HomogeneousPoint{x: point.x, y: point.y, z: one}
    for index in 2 until multiples.count do
        multiples[index] = p256HomogeneousAdd(multiples[index - 1], affine)

    var result = identity
    for window in 64
    {
        for 4 do
            result = p256HomogeneousDouble(result)

        let nibbleIndex = 63 - window
        let nibble      = (scalar[].limbs[nibbleIndex / 16] >> ((nibbleIndex % 16) * 4)) & 15
        var selected    = identity
        for index in 1 until multiples.count
        {
            let candidate = multiples[index]
            let matched = index == nibble
            selected.x = p256FieldSelect(selected.x, candidate.x, matched)
            selected.y = p256FieldSelect(selected.y, candidate.y, matched)
            selected.z = p256FieldSelect(selected.z, candidate.z, matched)
        }

        result = p256HomogeneousAddProjective(result, selected)
        Crypto.secureClear(Swag.makeSlice(&selected, 1))
    }

    let converted = p256HomogeneousToJacobian(result)
    Crypto.secureClear(Swag.makeSlice(&result, 1))
    return converted
}

// Verification alone uses direct indexing with digits from the public
// signature. ECDH continues to use the masked arbitrary-point multiplier.
private func p256MultiplyVerificationPoint(scalar: P256Field, point: P256Point)->P256HomogeneousPoint
{
    var digits: [257] s8
    var bit   = 0'u32
    var carry = 0'u64
    while bit < 256
    {
        let word = bit / 64
        let shift = bit % 64
        var window = scalar.limbs[word] >> shift
        if shift > 59 and word < 3 do
            window |= scalar.limbs[word + 1] << (64 - shift)

        let value = (window & 31) + carry
        if (value & 1) == 0
        {
            bit += 1
            continue
        }

        carry = value >> 4
        digits[bit] = cast(s8, value) - cast(s8, carry * 32)
        bit += 5
    }

    digits[256] = cast(s8, carry)
    var oddMultiples: [8] P256HomogeneousPoint
    let one = P256Field{limbs: P256MontgomeryOne}
    oddMultiples[0] = P256HomogeneousPoint{x: point.x, y: point.y, z: one}
    let doubled = p256HomogeneousDouble(oddMultiples[0])
    for index in 1 until oddMultiples.count do
        oddMultiples[index] = p256HomogeneousAddProjective(oddMultiples[index - 1], doubled)

    var result = P256HomogeneousPoint{y: one}
    for step in digits.count
    {
        result = p256HomogeneousDouble(result)
        let digit = digits[digits.count - 1 - step]
        if digit == 0 do
            continue

        let magnitude = digit < 0 ? -digit : digit
        var selected = oddMultiples[cast(u32, magnitude) / 2]
        if digit < 0 do
            selected.y = p256FieldSubtract(P256Field{}, selected.y)
        result = p256HomogeneousAddProjective(result, selected)
    }
    return result
}

private func p256MultiplyGenerator(scalar: const *P256Field)->P256Point
{
    const Steps = 8
    const Adjustment = P256Field{limbs: [0x0C46353D039CDAAE, 0x4319055258E8617B, 0x0000000000000000, 0x00000000FFFFFFFF]}
    const HalfMontgomery = P256Field{limbs: [0, 0, 0, 0x8000000000000000]}
    // Interpret all 256 bits of (scalar + 2^256 - 1) / 2 modulo the order
    // as signs. A bit of one contributes +2^i and a zero contributes -2^i.
    var adjusted = p256OrderMultiply(p256OrderAdd(scalar[], Adjustment), HalfMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&adjusted, 1))

    var result = P256HomogeneousPoint{y: P256Field{limbs: P256MontgomeryOne}}
    for step in Steps
    {
        result = p256HomogeneousDouble(result)
        for stripe in P256GeneratorComb.count
        {
            let shift   = Steps - 1 - step + stripe * Steps
            let digits0 = (adjusted.limbs[0] >> shift) & 1
            let digits1 = (adjusted.limbs[1] >> shift) & 1
            let digits2 = (adjusted.limbs[2] >> shift) & 1
            let digits3 = (adjusted.limbs[3] >> shift) & 1
            let digit   = digits0 | (digits1 << 1) | (digits2 << 2)
            let negate  = 0'u64 - (digits3 ^ 1)
            let entry   = digit ^ (negate & 7)

            var selection: P256AffinePoint
            for index in P256GeneratorComb[stripe].count
            {
                let matched = index == entry
                let point   = P256GeneratorComb[stripe][index]
                selection.x = p256FieldSelect(selection.x, point.x, matched)
                selection.y = p256FieldSelect(selection.y, point.y, matched)
            }

            // These finite table points have nonzero Y.
            var borrow = 0'u64
            for word in 4
            {
                let y          = selection.y.limbs[word]
                let difference = p256SubtractWord(P256Modulus[word], y, borrow)
                selection.y.limbs[word] = y ^ ((y ^ difference.word) & negate)
                borrow = difference.borrow
            }
            result = p256HomogeneousAdd(result, selection)
            Crypto.secureClear(Swag.makeSlice(&selection, 1))
        }
    }

    let converted = p256HomogeneousToJacobian(result)
    Crypto.secureClear(Swag.makeSlice(&result, 1))
    return converted
}

private func p256ValidatePublicPoint(point: P256Point)->bool
{
    let xSquared  = p256FieldSquare(point.x)
    let xCubed    = p256FieldMultiply(xSquared, point.x)
    let ySquared  = p256FieldSquare(point.y)
    let threeX    = p256FieldTriple(point.x)
    let expected  = p256FieldAdd(p256FieldSubtract(xCubed, threeX), P256MontgomeryB)
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
    if publicKey.count != P256PublicKeySize
    {
        fail Errors.BadParameterError{"P-256 public key output must be 65 bytes"}
    }

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
       peerPublicKey[0] != 4
    {
        fail Errors.BadParameterError{"P-256 ECDH needs a 65-byte uncompressed peer key and a 32-byte output"}
    }

    var scalar = try p256ScalarDecode(privateKey)
    defer Crypto.secureClear(Swag.makeSlice(&scalar, 1))
    var peer: P256Point
    peer.x       = try p256FieldDecode(peerPublicKey[1 until 33])
    peer.y       = try p256FieldDecode(peerPublicKey[33 until 65])
    peer.z.limbs = P256MontgomeryOne
    if not p256ValidatePublicPoint(peer)
    {
        fail Errors.BadParameterError{"P-256 peer public key is not on the curve"}
    }

    var shared = p256ScalarMultiply(&scalar, peer)
    defer Crypto.secureClear(Swag.makeSlice(&shared, 1))
    if p256FieldEqual(shared.z, P256Field{})
    {
        fail Errors.BadParameterError{"P-256 ECDH produced the point at infinity"}
    }

    p256FieldEncode(p256AffineX(shared), sharedSecret)
}

// Signs `message` with deterministic ECDSA using SHA-256 and a P-256 private scalar.
//
// `signature` must hold 64 bytes and receives the fixed-width, big-endian `r || s` encoding.
// The private scalar must be in the range 1 through the curve order minus one.
func p256EcdsaSign(privateKey, message: const [..] u8, signature: [..] u8) fail
{
    if signature.count != 64
    {
        fail Errors.BadParameterError{"P-256 ECDSA signature output must be 64 bytes"}
    }

    var privateScalar = try p256ScalarDecode(privateKey)
    defer Crypto.secureClear(Swag.makeSlice(&privateScalar, 1))
    var messageDigest = p256DigestBytes(Hash.Sha256.compute(message))
    defer Crypto.secureClear(Swag.makeSlice(&messageDigest, 1))
    var nonceBytes = p256Rfc6979Nonce(privateKey, messageDigest)
    defer Crypto.secureClear(Swag.makeSlice(&nonceBytes, 1))
    var nonce = try p256ScalarDecode(nonceBytes)
    defer Crypto.secureClear(Swag.makeSlice(&nonce, 1))

    var noncePoint = p256MultiplyGenerator(&nonce)
    defer Crypto.secureClear(Swag.makeSlice(&noncePoint, 1))
    var r = p256OrderReduce(p256FromMontgomery(p256AffineX(noncePoint)))
    if not p256ScalarIsValid(r)
    {
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid nonce"}
    }

    let zRaw = p256ReadInteger(messageDigest)
    var z    = p256OrderReduce(zRaw)
    defer Crypto.secureClear(Swag.makeSlice(&z, 1))

    var nonceMontgomery = p256OrderToMontgomery(nonce)
    defer Crypto.secureClear(Swag.makeSlice(&nonceMontgomery, 1))
    var rMontgomery = p256OrderToMontgomery(r)
    defer Crypto.secureClear(Swag.makeSlice(&rMontgomery, 1))
    var privateMontgomery = p256OrderToMontgomery(privateScalar)
    defer Crypto.secureClear(Swag.makeSlice(&privateMontgomery, 1))
    var zMontgomery = p256OrderToMontgomery(z)
    defer Crypto.secureClear(Swag.makeSlice(&zMontgomery, 1))

    var inverseNonce = p256OrderInverse(nonceMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&inverseNonce, 1))
    var rd = p256OrderMultiply(rMontgomery, privateMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&rd, 1))
    var sum = p256OrderAdd(zMontgomery, rd)
    defer Crypto.secureClear(Swag.makeSlice(&sum, 1))
    var sMontgomery = p256OrderMultiply(inverseNonce, sum)
    defer Crypto.secureClear(Swag.makeSlice(&sMontgomery, 1))
    var s = p256OrderFromMontgomery(sMontgomery)
    defer Crypto.secureClear(Swag.makeSlice(&s, 1))
    if not p256ScalarIsValid(s)
    {
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid signature"}
    }

    p256WriteInteger(r, signature[until 32])
    p256WriteInteger(s, signature[32 to])
    Crypto.secureClear(Swag.makeSlice(&r, 1))
}

// Verifies a fixed-width P-256 ECDSA signature over `message` using SHA-256.
//
// The public key must use SEC1 0x04 || X || Y encoding. Invalid public keys fail with
// [[Core.Errors.BadParameterError]]; a malformed or incorrect signature returns false.
func p256EcdsaVerify(publicKey, message, signature: const [..] u8)->bool fail
{
    if publicKey.count != P256PublicKeySize or publicKey[0] != 4 or signature.count != 64
    {
        fail Errors.BadParameterError{"P-256 ECDSA needs a 65-byte uncompressed key and a 64-byte signature"}
    }

    var publicPoint: P256Point
    publicPoint.x       = try p256FieldDecode(publicKey[1 until 33])
    publicPoint.y       = try p256FieldDecode(publicKey[33 until 65])
    publicPoint.z.limbs = P256MontgomeryOne
    if not p256ValidatePublicPoint(publicPoint)
    {
        fail Errors.BadParameterError{"P-256 ECDSA public key is not on the curve"}
    }

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
    let zRaw = p256ReadInteger(messageDigest)
    var z    = p256OrderReduce(zRaw)
    defer Crypto.secureClear(Swag.makeSlice(&z, 1))
    var rMontgomery = p256OrderToMontgomery(r)
    defer Crypto.secureClear(Swag.makeSlice(&rMontgomery, 1))
    var sMontgomery = p256OrderToMontgomery(s)
    defer Crypto.secureClear(Swag.makeSlice(&sMontgomery, 1))
    var inverseS = p256OrderInverse(sMontgomery)
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
    var second = p256HomogeneousToJacobian(p256MultiplyVerificationPoint(u2, publicPoint))
    defer Crypto.secureClear(Swag.makeSlice(&second, 1))
    var sum = p256PointAdd(first, second, p256PointDouble(first))
    defer Crypto.secureClear(Swag.makeSlice(&sum, 1))
    if p256FieldEqual(sum.z, P256Field{})
    {
        Crypto.secureClear(Swag.makeSlice(&r, 1))
        Crypto.secureClear(Swag.makeSlice(&s, 1))
        return false
    }

    // The affine X is either r or r + n because the field prime is below 2n.
    // Compare in Jacobian coordinates to avoid inverting the projective scale.
    let zSquared = p256FieldSquare(sum.z)
    let expected = p256FieldMultiply(p256ToMontgomery(r), zSquared)
    var valid    = p256FieldEqual(sum.x, expected)
    if not valid and p256LessThan(r, P256ModulusMinusOrder)
    {
        let candidate = p256AddMod(r, P256Field{limbs: P256Order}, P256Modulus)
        valid = p256FieldEqual(sum.x, p256FieldMultiply(p256ToMontgomery(candidate), zSquared))
    }

    Crypto.secureClear(Swag.makeSlice(&s, 1))
    Crypto.secureClear(Swag.makeSlice(&r, 1))
    return valid
}

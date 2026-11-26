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

private const P256InverseExponent: [8] u32 = [
    0xFFFFFFFD, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0xFFFFFFFF]

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

private func p256MontgomeryMultiply(left, right, modulus: [8] u32, n0Inverse: u32)->[8] u32
{
    var temporary: [9] u32
    for index in 8
    {
        var carry = 0'u64
        for word in 8
        {
            let product = cast(u64, left[word]) * right[index] + temporary[word] + carry
            temporary[word] = cast(u32, product)
            carry = product >> 32
        }

        let productTop = cast(u64, temporary[8]) + carry
        temporary[8] = cast(u32, productTop)
        let reduction = temporary[0] * n0Inverse
        carry = 0
        for word in 8
        {
            let product = cast(u64, reduction) * modulus[word] + temporary[word] + carry
            if word do
                temporary[word - 1] = cast(u32, product)
            carry = product >> 32
        }

        let top = cast(u64, temporary[8]) + carry
        temporary[7] = cast(u32, top)
        temporary[8] = cast(u32, top >> 32)
    }

    var difference: [8] u32
    var borrow = 0'u64
    for index in 8
    {
        let subtrahend = cast(u64, modulus[index]) + borrow
        let word       = cast(u64, temporary[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let useDifference = cast(u32, temporary[8] != 0) | cast(u32, borrow == 0)
    let mask = 0'u32 - useDifference
    var result: #returntype
    for index in 8 do
        result[index] = (difference[index] & mask) | (temporary[index] & ~mask)
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

private func p256FieldPower(value: P256Field, exponent: [8] u32)->P256Field
{
    var result: P256Field
    result.limbs = P256MontgomeryOne
    for step in 256
    {
        let bit = 255 - step
        result = p256FieldSquare(result)
        if (exponent[bit / 32] >> (bit % 32)) & 1 do
            result = p256FieldMultiply(result, value)
    }

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
    result.limbs = p256MontgomeryMultiply(left.limbs, right.limbs, P256Order, 0xEE00BC4F)
    return result
}

private func p256OrderToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, P256OrderMontgomeryR2, P256Order, 0xEE00BC4F)
    return result
}

private func p256OrderFromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0, 0, 0, 0, 0], P256Order, 0xEE00BC4F)
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
    let h         = p256FieldSubtract(u2, u1)
    let r         = p256FieldSubtract(s2, s1)
    let hSquared  = p256FieldSquare(h)
    let hCubed    = p256FieldMultiply(h, hSquared)
    let u1h2      = p256FieldMultiply(u1, hSquared)
    let x3        = p256FieldSubtract(p256FieldSubtract(p256FieldSquare(r), hCubed), p256FieldDouble(u1h2))
    let y3        = p256FieldSubtract(p256FieldMultiply(r, p256FieldSubtract(u1h2, x3)), p256FieldMultiply(s1, hCubed))
    let z3        = p256FieldMultiply(h, p256FieldMultiply(left.z, right.z))
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

private func p256Generator()->P256Point
{
    var result: #returntype
    var x:      P256Field
    x.limbs = [0xD898C296, 0xF4A13945, 0x2DEB33A0, 0x77037D81,
               0x63A440F2, 0xF8BCE6E5, 0xE12C4247, 0x6B17D1F2]
    var y: P256Field
    y.limbs = [0x37BF51F5, 0xCBB64068, 0x6B315ECE, 0x2BCE3357,
               0x7C0F9E16, 0x8EE7EB4A, 0xFE1A7F9B, 0x4FE342E2]
    result.x       = p256ToMontgomery(x)
    result.y       = p256ToMontgomery(y)
    result.z.limbs = P256MontgomeryOne
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
    var inverse = p256FieldPower(point.z, P256InverseExponent)
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
    var point = p256ScalarMultiply(&scalar, p256Generator())
    defer Crypto.secureClear(Swag.makeSlice(&point, 1))

    var inverse = p256FieldPower(point.z, P256InverseExponent)
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

    var noncePoint = p256ScalarMultiply(&nonce, p256Generator())
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

    var first = p256ScalarMultiply(&u1, p256Generator())
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

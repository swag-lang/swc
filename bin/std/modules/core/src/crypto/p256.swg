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

private func p256MontgomeryMultiply(left, right: [8] u32)->[8] u32
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
        let reduction = temporary[0]
        carry = 0
        for word in 8
        {
            let product = cast(u64, reduction) * P256Modulus[word] + temporary[word] + carry
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
        let subtrahend = cast(u64, P256Modulus[index]) + borrow
        let word       = cast(u64, temporary[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let useDifference = cast(u32, (temporary[8] != 0) or (borrow == 0))
    let mask = 0'u32 - useDifference
    var result: #returntype
    for index in 8 do
        result[index] = (difference[index] & mask) | (temporary[index] & ~mask)
    return result
}

private func p256ToMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, P256MontgomeryR2)
    return result
}

private func p256FromMontgomery(value: P256Field)->P256Field
{
    var result: #returntype
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0, 0, 0, 0, 0])
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

    let useDifference = cast(u32, (carry != 0) or (borrow == 0))
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
    result.limbs = p256MontgomeryMultiply(left.limbs, right.limbs)
    return result
}

private func p256FieldSquare(value: P256Field)->P256Field => p256FieldMultiply(value, value)

private func p256FieldSmall(value: P256Field, factor: u32)->P256Field
{
    var result: P256Field
    var iteration = 0'u32
    while iteration < factor
    {
        result    = p256FieldAdd(result, value)
        iteration += 1
    }

    return result
}

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

    var lessThanOrder = false
    var index         = 8'u32
    while index
    {
        index -= 1
        if result.limbs[index] < P256Order[index]
        {
            lessThanOrder = true
            break
        }

        if result.limbs[index] > P256Order[index] do
            break
    }

    var nonZero = 0'u32
    for word in result.limbs do
        nonZero |= word
    if not lessThanOrder or not nonZero do
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
    let alpha = p256FieldSmall(p256FieldMultiply(p256FieldSubtract(point.x, delta), p256FieldAdd(point.x, delta)), 3)

    var result: P256Point
    let alphaSquared = p256FieldSquare(alpha)
    let eightBeta    = p256FieldSmall(beta, 8)
    result.x = p256FieldSubtract(alphaSquared, eightBeta)

    let fourBeta          = p256FieldSmall(beta, 4)
    let gammaSquared      = p256FieldSquare(gamma)
    let eightGammaSquared = p256FieldSmall(gammaSquared, 8)
    result.y = p256FieldSubtract(p256FieldMultiply(alpha, p256FieldSubtract(fourBeta, result.x)), eightGammaSquared)

    let yzSquared = p256FieldSquare(p256FieldAdd(point.y, point.z))
    result.z = p256FieldSubtract(p256FieldSubtract(yzSquared, gamma), delta)
    return result
}

private func p256PointAdd(left, right: P256Point)->P256Point
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
    let x3        = p256FieldSubtract(p256FieldSubtract(p256FieldSquare(r), hCubed), p256FieldSmall(u1h2, 2))
    let y3        = p256FieldSubtract(p256FieldMultiply(r, p256FieldSubtract(u1h2, x3)), p256FieldMultiply(s1, hCubed))
    let z3        = p256FieldMultiply(h, p256FieldMultiply(left.z, right.z))
    var sum: P256Point
    sum.x = x3
    sum.y = y3
    sum.z = z3

    let infinity = p256Infinity()
    let doubled  = p256PointDouble(left)
    let sameX    = p256FieldEqual(u1, u2)
    let sameY    = p256FieldEqual(s1, s2)
    var result   = p256PointSelect(sum, doubled, sameX and sameY)
    result = p256PointSelect(result, infinity, sameX and not sameY)
    result = p256PointSelect(result, right, p256FieldEqual(left.z, P256Field{}))
    result = p256PointSelect(result, left, p256FieldEqual(right.z, P256Field{}))
    return result
}

private func p256ConditionalSwap(left, right: *P256Point, swap: u32)
{
    let mask = 0'u32 - swap
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
    var low  = p256Infinity()
    var high = point
    for step in 256
    {
        let bitIndex = 255 - step
        let bit      = (scalar[].limbs[bitIndex / 32] >> (bitIndex % 32)) & 1
        p256ConditionalSwap(&low, &high, bit)
        let sum     = p256PointAdd(low, high)
        let doubled = p256PointDouble(low)
        low  = doubled
        high = sum
        p256ConditionalSwap(&low, &high, bit)
    }

    var result = low
    Crypto.secureClear(Swag.makeSlice(&low, 1))
    Crypto.secureClear(Swag.makeSlice(&high, 1))
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
    let threeX    = p256FieldSmall(point.x, 3)
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

private func p256AffineY(point: P256Point)->P256Field
{
    var inverse = p256FieldPower(point.z, P256InverseExponent)
    let result  = p256FieldMultiply(point.y, p256FieldMultiply(p256FieldSquare(inverse), inverse))
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
    publicKey[0] = 4
    p256FieldEncode(p256AffineX(point), publicKey[1 until 33])
    p256FieldEncode(p256AffineY(point), publicKey[33 until 65])
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

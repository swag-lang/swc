#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Ed25519 private seeds and public keys are 32 bytes; signatures are 64 bytes.
public const Ed25519KeySize = 32

// Ed25519 signature size in bytes.
public const Ed25519SignatureSize = 64

private const Ed25519Order: [16] u32 = [
    0xD3ED, 0x5CF5, 0x631A, 0x5812, 0x9CD6, 0xA2F7, 0xF9DE, 0x14DE,
    0, 0, 0, 0, 0, 0, 0, 0x1000]

private struct Ed25519Point
{
    x: X25519Field
    y: X25519Field
    z: X25519Field
    t: X25519Field
}

private func ed25519FieldConstant(limbs: [16] u64)->X25519Field
{
    var result: #returntype
    result.limbs = limbs
    return result
}

private func ed25519D()->X25519Field
{
    return ed25519FieldConstant([0x78A3, 0x1359, 0x4DCA, 0x75EB, 0xD8AB, 0x4141, 0x0A4D, 0x0070,
                                 0xE898, 0x7779, 0x4079, 0x8CC7, 0xFE73, 0x2B6F, 0x6CEE, 0x5203])
}

private func ed25519SqrtMinusOne()->X25519Field
{
    return ed25519FieldConstant([0xA0B0, 0x4A0E, 0x1B27, 0xC4EE, 0xE478, 0xAD2F, 0x1806, 0x2F43,
                                 0xD7A7, 0x3DFB, 0x0099, 0x2B4D, 0xDF0B, 0x4FC1, 0x2480, 0x2B83])
}

private func ed25519Identity()->Ed25519Point
{
    var result: #returntype
    result.y.limbs[0] = 1
    result.z.limbs[0] = 1
    return result
}

private func ed25519FieldEqual(left, right: X25519Field)->bool
{
    var leftBytes:  [32] u8
    var rightBytes: [32] u8
    x25519Encode(left, leftBytes)
    x25519Encode(right, rightBytes)
    return Crypto.constantTimeEqual(leftBytes, rightBytes)
}

private func ed25519Add(left, right: Ed25519Point)->Ed25519Point
{
    let a  = x25519Multiply(x25519Subtract(left.y, left.x), x25519Subtract(right.y, right.x))
    let b  = x25519Multiply(x25519Add(left.y, left.x), x25519Add(right.y, right.x))
    let c  = x25519Multiply(ed25519D(), x25519Multiply(left.t, right.t))
    let c2 = x25519Add(c, c)
    let d  = x25519Add(x25519Multiply(left.z, right.z), x25519Multiply(left.z, right.z))
    let e  = x25519Subtract(b, a)
    let f  = x25519Subtract(d, c2)
    let g  = x25519Add(d, c2)
    let h  = x25519Add(b, a)
    var result: #returntype
    result.x = x25519Multiply(e, f)
    result.y = x25519Multiply(g, h)
    result.t = x25519Multiply(e, h)
    result.z = x25519Multiply(f, g)
    return result
}

private func ed25519Double(point: Ed25519Point)->Ed25519Point
{
    let a  = x25519Square(point.x)
    let b  = x25519Square(point.y)
    let c  = x25519Square(point.z)
    let c2 = x25519Add(c, c)
    var zero:   X25519Field
    let d  = x25519Subtract(zero, a)
    let e  = x25519Subtract(x25519Subtract(x25519Square(x25519Add(point.x, point.y)), a), b)
    let g  = x25519Add(d, b)
    let f  = x25519Subtract(g, c2)
    let h  = x25519Subtract(d, b)
    var result: #returntype
    result.x = x25519Multiply(e, f)
    result.y = x25519Multiply(g, h)
    result.t = x25519Multiply(e, h)
    result.z = x25519Multiply(f, g)
    return result
}

private func ed25519Select(left, right: Ed25519Point, chooseRight: u64)->Ed25519Point
{
    let mask = 0'u64 - chooseRight
    var result: #returntype
    for index in 16
    {
        result.x.limbs[index] = (left.x.limbs[index] & ~mask) | (right.x.limbs[index] & mask)
        result.y.limbs[index] = (left.y.limbs[index] & ~mask) | (right.y.limbs[index] & mask)
        result.z.limbs[index] = (left.z.limbs[index] & ~mask) | (right.z.limbs[index] & mask)
        result.t.limbs[index] = (left.t.limbs[index] & ~mask) | (right.t.limbs[index] & mask)
    }

    return result
}

private func ed25519ScalarMultiply(point: Ed25519Point, scalar: const [..] u8)->Ed25519Point
{
    var result = ed25519Identity()
    var addend = point
    var bit    = 0'u32
    while bit < 256
    {
        let selected = cast(u64, (scalar[bit / 8] >> (bit & 7)) & 1)
        result = ed25519Select(result, ed25519Add(result, addend), selected)
        addend = ed25519Double(addend)
        bit    += 1
    }

    return result
}

private func ed25519BasePoint()->Ed25519Point
{
    var result: #returntype
    result.x = ed25519FieldConstant([0xD51A, 0x8F25, 0x2D60, 0xC956, 0xA7B2, 0x9525, 0xC760, 0x692C,
                                     0xDC5C, 0xFDD6, 0xE231, 0xC0A4, 0x53FE, 0xCD6E, 0x36D3, 0x2169])
    result.y = ed25519FieldConstant([0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
                                     0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666])
    result.z.limbs[0] = 1
    result.t = x25519Multiply(result.x, result.y)
    return result
}

private func ed25519HashSeed(seed: const [..] u8)->[64] u8
{
    var hash: Hash.Sha512
    hash.reset()
    hash.update(seed)
    return ed25519HashFinalize(&hash)
}

private func ed25519DecodePoint(encoded: const [..] u8)->(Ed25519Point, bool)
{
    var yBytes: [32] u8
    Swag.memcpy(&yBytes[0], encoded.buffer, 32)
    let sign = yBytes[31] >> 7
    yBytes[31] &= 0x7F
    let y = x25519Decode(yBytes)
    var canonicalY: [32] u8
    x25519Encode(y, canonicalY)
    if not Crypto.constantTimeEqual(yBytes, canonicalY) do
        return (ed25519Identity(), false)

    var one: X25519Field
    one.limbs[0] = 1
    let ySquared    = x25519Square(y)
    let numerator   = x25519Subtract(ySquared, one)
    let denominator = x25519Add(x25519Multiply(ed25519D(), ySquared), one)
    let xSquared    = x25519Multiply(numerator, x25519Invert(denominator))

    // sqrt(u) = u^((p+3)/8), with the standard sqrt(-1) correction.
    var x: X25519Field
    x.limbs[0] = 1
    var bit = 252'u32
    while bit
    {
        bit -= 1
        x   = x25519Square(x)
        if bit do
            x = x25519Multiply(x, xSquared)
    }

    if not ed25519FieldEqual(x25519Square(x), xSquared)
    {
        x = x25519Multiply(x, ed25519SqrtMinusOne())
        if not ed25519FieldEqual(x25519Square(x), xSquared) do
            return (ed25519Identity(), false)
    }

    var xBytes: [32] u8
    x25519Encode(x, xBytes)
    var xNonzero = 0'u8
    for byte in xBytes do
        xNonzero |= byte
    if not xNonzero and sign do
        return (ed25519Identity(), false)
    if (xBytes[0] & 1) != sign
    {
        var zero: X25519Field
        x = x25519Subtract(zero, x)
    }

    var result: Ed25519Point
    result.x = x
    result.y = y
    result.z.limbs[0] = 1
    result.t = x25519Multiply(x, y)
    Crypto.secureClear(yBytes)
    Crypto.secureClear(canonicalY)
    Crypto.secureClear(xBytes)
    return (result, true)
}

private func ed25519EncodePoint(point: Ed25519Point)->[32] u8
{
    let inverseZ = x25519Invert(point.z)
    let x        = x25519Multiply(point.x, inverseZ)
    let y        = x25519Multiply(point.y, inverseZ)
    var result: [32] u8
    x25519Encode(y, result)
    var xBytes: [32] u8
    x25519Encode(x, xBytes)
    result[31] |= (xBytes[0] & 1) << 7
    Crypto.secureClear(xBytes)
    return result
}

private func ed25519HashFinalize(hash: *Hash.Sha512)->[64] u8
{
    let words = hash[].finalize()
    var result: #returntype
    for word in 8
    {
        for byte in 8
        {
            let shift = cast(u32, (7 - byte) * 8)
            result[word * 8 + byte] = cast(u8, (words[word] >> shift) & 0xFF)
        }
    }

    hash[].clear()
    return result
}

private func ed25519Reduce(digest: const [..] u8)->[32] u8
{
    var remainder: [16] u32
    var bit = digest.count * 8
    while bit
    {
        bit -= 1
        var carry = cast(u32, (digest[bit / 8] >> (bit & 7)) & 1)
        for index in 16
        {
            let value = (remainder[index] << 1) | carry
            remainder[index] = value & 0xFFFF
            carry = value >> 16
        }

        var difference: [16] u32
        var borrow = 0'u32
        for index in 16
        {
            let sub       = Ed25519Order[index] + borrow
            let underflow = remainder[index] < sub
            difference[index] = (remainder[index] - sub) & 0xFFFF
            borrow = cast(u32, underflow)
        }

        let mask = 0'u32 - (1 - borrow)
        for index in 16 do
            remainder[index] = (difference[index] & mask) | (remainder[index] & ~mask)
    }

    var result: #returntype
    for index in 16
    {
        result[index * 2]     = cast(u8, remainder[index] & 0xFF)
        result[index * 2 + 1] = cast(u8, remainder[index] >> 8)
    }

    return result
}

private func ed25519ScalarMultiplyAdd(left, right, addend: const [..] u8)->[32] u8
{
    var leftDigits:   [16] u64
    var rightDigits:  [16] u64
    var addendDigits: [16] u64
    for index in 16
    {
        let offset = index * 2
        leftDigits[index]   = cast(u64, left[offset]) | (cast(u64, left[offset + 1]) << 8)
        rightDigits[index]  = cast(u64, right[offset]) | (cast(u64, right[offset + 1]) << 8)
        addendDigits[index] = cast(u64, addend[offset]) | (cast(u64, addend[offset + 1]) << 8)
    }

    var wide: [32] u64
    for i in 16
    {
        for j in 16 do
            wide[i + j] += leftDigits[i] * rightDigits[j]
    }

    for index in 16 do
        wide[index] += addendDigits[index]
    for index in 31
    {
        let carry = wide[index] >> 16
        wide[index]     &= 0xFFFF
        wide[index + 1] += carry
    }

    var bytes: [64] u8
    for index in 32
    {
        bytes[index * 2]     = cast(u8, wide[index] & 0xFF)
        bytes[index * 2 + 1] = cast(u8, wide[index] >> 8)
    }

    let result = ed25519Reduce(bytes)
    Crypto.secureClear(leftDigits)
    Crypto.secureClear(rightDigits)
    Crypto.secureClear(addendDigits)
    Crypto.secureClear(wide)
    Crypto.secureClear(bytes)
    return result
}

private func ed25519IsCanonicalScalar(value: const [..] u8)->bool
{
    var wide: [64] u8
    Swag.memcpy(&wide[0], value.buffer, 32)
    let reduced = ed25519Reduce(wide)
    return Crypto.constantTimeEqual(value, reduced)
}

private func ed25519IsIdentity(point: Ed25519Point)->bool
{
    let encoded = ed25519EncodePoint(point)
    var identity: [32] u8
    identity[0] = 1
    return Crypto.constantTimeEqual(encoded, identity)
}

private func ed25519IsPrimeSubgroup(point: Ed25519Point)->bool
{
    var order: [32] u8
    for index in 16
    {
        order[index * 2]     = cast(u8, Ed25519Order[index] & 0xFF)
        order[index * 2 + 1] = cast(u8, Ed25519Order[index] >> 8)
    }

    let multiple = ed25519ScalarMultiply(point, order)
    return ed25519IsIdentity(multiple) and not ed25519IsIdentity(ed25519Double(ed25519Double(ed25519Double(point))))
}

private func ed25519PublicKeyFromExpanded(expanded: [64] u8)->[32] u8
{
    var scalar: [32] u8
    Swag.memcpy(&scalar[0], &expanded[0], 32)

    scalar[0]  &= 248
    scalar[31] &= 63
    scalar[31] |= 64
    var point   = ed25519ScalarMultiply(ed25519BasePoint(), scalar)
    let encoded = ed25519EncodePoint(point)
    Crypto.secureClear(point.x.limbs)
    Crypto.secureClear(point.y.limbs)
    Crypto.secureClear(point.z.limbs)
    Crypto.secureClear(point.t.limbs)
    Crypto.secureClear(scalar)
    return encoded
}

// Derives the Ed25519 public key corresponding to a 32-byte private seed.
//
// Fails with [[Core.Errors.BadParameterError]] unless the seed and destination are exactly 32 bytes.
func ed25519PublicKey(privateSeed: const [..] u8, destination: [..] u8) fail
{
    if privateSeed.count != Ed25519KeySize or destination.count != Ed25519KeySize do
        fail Errors.BadParameterError{"Ed25519 seeds and public keys must be exactly 32 bytes"}

    var expanded = ed25519HashSeed(privateSeed)
    let encoded  = ed25519PublicKeyFromExpanded(expanded)
    Swag.memcpy(destination.buffer, &encoded[0], Ed25519KeySize)
    Crypto.secureClear(expanded)
}

// Signs `message` with a 32-byte Ed25519 seed and writes the 64-byte RFC 8032 signature.
//
// Fails with [[Core.Errors.BadParameterError]] unless the seed is 32 bytes and the output is 64 bytes.
func ed25519Sign(privateSeed, message: const [..] u8, signature: [..] u8) fail
{
    if privateSeed.count != Ed25519KeySize or signature.count != Ed25519SignatureSize do
        fail Errors.BadParameterError{"Ed25519 needs a 32-byte seed and a 64-byte signature output"}

    var expanded = ed25519HashSeed(privateSeed)
    var scalar: [32] u8
    var prefix: [32] u8
    for index in 32
    {
        scalar[index] = expanded[index]
        prefix[index] = expanded[index + 32]
    }

    scalar[0]  &= 248
    scalar[31] &= 63
    scalar[31] |= 64

    var nonceHash: Hash.Sha512
    nonceHash.reset()
    nonceHash.update(prefix)
    nonceHash.update(message)
    let nonceDigest = ed25519HashFinalize(&nonceHash)
    let nonce       = ed25519Reduce(nonceDigest)
    var noncePoint  = ed25519ScalarMultiply(ed25519BasePoint(), nonce)
    let encodedR    = ed25519EncodePoint(noncePoint)
    Crypto.secureClear(noncePoint.x.limbs)
    Crypto.secureClear(noncePoint.y.limbs)
    Crypto.secureClear(noncePoint.z.limbs)
    Crypto.secureClear(noncePoint.t.limbs)

    let publicKey = ed25519PublicKeyFromExpanded(expanded)
    var challengeHash: Hash.Sha512
    challengeHash.reset()
    challengeHash.update(encodedR)
    challengeHash.update(publicKey)
    challengeHash.update(message)
    let challengeDigest = ed25519HashFinalize(&challengeHash)
    let challenge       = ed25519Reduce(challengeDigest)
    let response        = ed25519ScalarMultiplyAdd(challenge, scalar, nonce)
    Swag.memcpy(signature.buffer, &encodedR[0], 32)
    Swag.memcpy(signature.buffer + 32, &response[0], 32)
    Crypto.secureClear(scalar)
    Crypto.secureClear(prefix)
    Crypto.secureClear(nonceDigest)
    Crypto.secureClear(challengeDigest)
    Crypto.secureClear(nonce)
    Crypto.secureClear(challenge)
    Crypto.secureClear(response)
    Crypto.secureClear(expanded)
}

// Verifies an Ed25519 signature; malformed encodings and noncanonical scalars return false.
//
// Requires a 32-byte public key and 64-byte signature. Invalid lengths fail with
// [[Core.Errors.BadParameterError]]; invalid signatures return `false`.
func ed25519Verify(publicKey, message, signature: const [..] u8)->bool fail
{
    if publicKey.count != Ed25519KeySize or signature.count != Ed25519SignatureSize do
        fail Errors.BadParameterError{"Ed25519 needs a 32-byte public key and a 64-byte signature"}

    let encodedR = signature[until 32]
    let encodedS = signature[32 to]
    if not ed25519IsCanonicalScalar(encodedS) do
        return false

    let (publicPoint, validPublic) = ed25519DecodePoint(publicKey)
    let (rPoint, validR) = ed25519DecodePoint(encodedR)
    if not validPublic or
       not validR or
       not ed25519IsPrimeSubgroup(publicPoint) or
       not ed25519IsPrimeSubgroup(rPoint) do
        return false

    var challengeHash: Hash.Sha512
    challengeHash.reset()
    challengeHash.update(encodedR)
    challengeHash.update(publicKey)
    challengeHash.update(message)
    let challengeDigest = ed25519HashFinalize(&challengeHash)
    let challenge       = ed25519Reduce(challengeDigest)
    let left            = ed25519ScalarMultiply(ed25519BasePoint(), encodedS)
    let right           = ed25519Add(rPoint, ed25519ScalarMultiply(publicPoint, challenge))
    let verified        = Crypto.constantTimeEqual(ed25519EncodePoint(left), ed25519EncodePoint(right))
    Crypto.secureClear(challengeDigest)
    Crypto.secureClear(challenge)
    return verified
}

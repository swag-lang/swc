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
    let product = Math.mulU64(left, right)
    let sum     = product.lo + addend
    let word    = sum + carry
    let high    = product.hi + cast(u64, sum < product.lo) + cast(u64, word < sum)
    return {word, high}
}

private func p256MontgomeryMultiply(left, right, modulus: [4] u64, n0Inverse: u64)->[4] u64
{
    var temporary: [5] u64
    for multiplier in right
    {
        var carry = 0'u64
        for word in 4
        {
            let product = p256MultiplyAdd(left[word], multiplier, temporary[word], carry)
            temporary[word] = product.word
            carry = product.carry
        }

        let productTop   = temporary[4] + carry
        let productCarry = cast(u64, productTop < carry)
        let reduction    = temporary[0] * n0Inverse
        carry = p256MultiplyAdd(reduction, modulus[0], temporary[0], 0).carry
        for word in 1 until 4
        {
            let product = p256MultiplyAdd(reduction, modulus[word], temporary[word], carry)
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
        let word = temporary[index] - modulus[index]
        difference[index] = word - borrow
        borrow = cast(u64, temporary[index] < modulus[index]) | cast(u64, word < borrow)
    }

    let useDifference = cast(u64, temporary[4] != 0) | cast(u64, borrow == 0)
    let mask = 0'u64 - useDifference
    var result: #returntype
    for index in 4 do
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
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0], P256Modulus, 1)
    return result
}

#[Swag.Inline]
private func p256AddWord(left, right, carry: u64)->{word: u64, carry: u64}
{
    let sum  = left + right
    let word = sum + carry
    return {word, cast(u64, sum < left) | cast(u64, word < sum)}
}

#[Swag.Inline]
private func p256SubtractWord(left, right, borrow: u64)->{word: u64, borrow: u64}
{
    let difference = left - right
    return {difference - borrow, cast(u64, left < right) | cast(u64, difference < borrow)}
}

private func p256Reduce(value: P256Field, modulus: [4] u64, high: u64)->P256Field
{
    var reduced: P256Field
    var borrow = 0'u64
    for index in 4
    {
        let difference = p256SubtractWord(value.limbs[index], modulus[index], borrow)
        reduced.limbs[index] = difference.word
        borrow = difference.borrow
    }

    let useReduced = cast(u64, high != 0) | cast(u64, borrow == 0)
    return p256FieldSelect(value, reduced, useReduced != 0)
}

private func p256AddMod(left, right: P256Field, modulus: [4] u64)->P256Field
{
    var result: P256Field
    var carry = 0'u64
    for index in 4
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

    return result
}

private func p256FieldAdd(left, right: P256Field)->P256Field => p256AddMod(left, right, P256Modulus)

private func p256FieldSubtract(left, right: P256Field)->P256Field => p256SubtractMod(left, right, P256Modulus)

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
    var difference = 0'u64
    for index in 4 do
        difference |= left.limbs[index] ^ right.limbs[index]
    return difference == 0
}

private func p256FieldSelect(left, right: P256Field, selectRight: bool)->P256Field
{
    let mask = 0'u64 - cast(u64, selectRight)
    var result: #returntype
    for index in 4 do
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

private func p256OrderAdd(left, right: P256Field)->P256Field => p256AddMod(left, right, P256Order)

private func p256OrderSubtract(left, right: P256Field)->P256Field => p256SubtractMod(left, right, P256Order)

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
    result.limbs = p256MontgomeryMultiply(value.limbs, [1, 0, 0, 0], P256Order, P256OrderWordInverse)
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
        for 4 do
            result = p256OrderMultiply(result, result)

        let nibbleIndex = 62 - window
        let digit       = (P256OrderInverseExponent[nibbleIndex / 16] >> ((nibbleIndex % 16) * 4)) & 15
        if digit do
            result = p256OrderMultiply(result, powers[digit])
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
    var borrow = 0'u64
    for index in 4 do
        borrow = p256SubtractWord(value.limbs[index], bound[index], borrow).borrow
    return borrow != 0
}

private func p256ScalarIsValid(value: P256Field)->bool
{
    let nonZero = not p256FieldEqual(value, P256Field{})
    return p256LessThan(value, P256Order) and nonZero
}

private func p256DigestBytes(digest: Hash.Sha256.Digest)->[32] u8
{
    var result: #returntype
    let words = cast([*] u32, result.buffer)
    for index in digest.count do
        words[index] = Math.nativeToBigEndian(digest[index])
    return result
}

internal func p256Rfc6979Nonce(privateKey: const [..] u8, digest: [32] u8)->[32] u8
{
    Swag.assert(privateKey.count == P256ScalarSize)
    var key:      [32] u8
    var value:    [32] u8
    var material: [97] u8
    defer
    {
        Crypto.secureClear(key)
        Crypto.secureClear(value)
        Crypto.secureClear(material)
    }

    Memory.set(value.buffer, 1'u8, value.count)
    Swag.memcpy(material.buffer + 33, privateKey.buffer, P256ScalarSize)

    // RFC 6979 bits2octets reduces the SHA-256 digest modulo the group order.
    p256WriteInteger(p256OrderReduce(p256ReadInteger(digest)), material[65 to])
    for marker in [0'u8, 1]
    {
        Swag.memcpy(material.buffer, value.buffer, value.count)
        material[32] = marker
        key          = HmacSha256.compute(key, material)
        value        = HmacSha256.compute(key, value)
    }

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

        Swag.memcpy(material.buffer, value.buffer, value.count)
        material[32] = 0
        key          = HmacSha256.compute(key, material[until 33])
        value        = HmacSha256.compute(key, value)
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
    if bytes.count != P256ScalarSize do
        fail Errors.BadParameterError{"P-256 coordinates and scalars must be 32 bytes"}
    let coordinate = p256ReadInteger(bytes)
    if not p256LessThan(coordinate, P256Modulus) do
        fail Errors.BadParameterError{"P-256 coordinate must be smaller than the field modulus"}
    return p256ToMontgomery(coordinate)
}

private func p256ScalarDecode(bytes: const [..] u8)->P256Field fail
{
    if bytes.count != P256ScalarSize do
        fail Errors.BadParameterError{"P-256 private scalar must be 32 bytes"}
    var scalar = p256ReadInteger(bytes)
    if not p256ScalarIsValid(scalar)
    {
        Crypto.secureClear(Swag.makeSlice(&scalar, 1))
        fail Errors.BadParameterError{"P-256 private scalar must be between 1 and the curve order minus one"}
    }

    return scalar
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
        let nibble      = (scalar[].limbs[nibbleIndex / 16] >> ((nibbleIndex % 16) * 4)) & 15
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
    {P256Field{limbs: [0x79E730D418A9143C, 0x75BA95FC5FEDB601, 0x79FB732B77622510, 0x18905F76A53755C6]},
     P256Field{limbs: [0xDDF25357CE95560A, 0x8B4AB8E4BA19E45C, 0xD2E88688DD21F325, 0x8571FF1825885D85]}},
    {P256Field{limbs: [0x4F922FC516A0D2BB, 0x0D5CC16C1A623499, 0x9241CF3A57C62C8B, 0x2F5E6961FD1B667F]},
     P256Field{limbs: [0x5C15C70BF5A01797, 0x3D20B44D60956192, 0x04911B37071FDB52, 0xF648F9168D6F0F7B]}},
    {P256Field{limbs: [0x9E566847E137BBBC, 0xE434469E8A6A0BEC, 0xB1C4276179D73463, 0x5ABE0285133D0015]},
     P256Field{limbs: [0x92AA837CC04C7DAB, 0x573D9F4C43260C07, 0x0C93156278E6CC37, 0x94BB725B6B6F7383]}},
    {P256Field{limbs: [0x62A8C244BFE20925, 0x91C19AC38FDCE867, 0x5A96A5D5DD387063, 0x61D587D421D324F6]},
     P256Field{limbs: [0xE87673A2A37173EA, 0x2384800853778B65, 0x10F8441E05BAB43E, 0xFA11FE124621EFBE]}},
    {P256Field{limbs: [0x1C891F2B2CB19FFD, 0x01BA8D5BB1923C23, 0xB6D03D678AC5CA8E, 0x586EB04C1F13BEDC]},
     P256Field{limbs: [0x0C35C6E527E8ED09, 0x1E81A33C1819EDE2, 0x278FD6C056C652FA, 0x19D5AC0870864F11]}},
    {P256Field{limbs: [0x62577734D2B533D5, 0x673B8AF6A1BDDDC0, 0x577E7C9AA79EC293, 0xBB6DE651C3B266B1]},
     P256Field{limbs: [0xE7E9303AB65259B3, 0xD6A0AFD3D03A7480, 0xC5AC83D19B3CFC27, 0x60B4619A5D18B99B]}},
    {P256Field{limbs: [0xBD6A38E11AE5AA1C, 0xB8B7652B49E73658, 0x0B130014EE5F87ED, 0x9D0F27B2AEEBFFCD]},
     P256Field{limbs: [0xCA9246317A730A55, 0x9C955B2FDDBBC83A, 0x07C1DFE0AC019A71, 0x244A566D356EC48D]}},
    {P256Field{limbs: [0x56F8410EF4F8B16A, 0x97241AFEC47B266A, 0x0A406B8E6D9C87C1, 0x803F3E02CD42AB1B]},
     P256Field{limbs: [0x7F0309A804DBEC69, 0xA83B85F73BBAD05F, 0xC6097273AD8E197F, 0xC097440E5067ADC1]}},
    {P256Field{limbs: [0x846A56F2C379AB34, 0xA8EE068B841DF8D1, 0x20314459176C68EF, 0xF1AF32D5915F1F30]},
     P256Field{limbs: [0x99C375315D75BD50, 0x837CFFBAF72F67BC, 0x0613A41848D7723F, 0x23D0F130E2D41C8B]}},
    {P256Field{limbs: [0xED93E225D5BE5A2B, 0x6FE799835934F3C6, 0x4314092622626FFC, 0x50BBB4D97990216A]},
     P256Field{limbs: [0x378191C6E57EC63E, 0x65422C40181DCDB2, 0x41A8099B0236E0F6, 0x2B10011801FE49C3]}},
    {P256Field{limbs: [0xFC68B5C59B391593, 0xC385F5A2598270FC, 0x7144F3AAD19ADCBB, 0xDD55899983FBAE0C]},
     P256Field{limbs: [0x93B88B8E74B82FF4, 0xD2E03C4071E734C9, 0x9A7A9EAF43C0322A, 0xE6E4C551149D6041]}},
    {P256Field{limbs: [0x5FE14BFE80EC21FE, 0xF6CE116AC255BE82, 0x98BC5A072F4A5D67, 0xFAD27148DB7E63AF]},
     P256Field{limbs: [0x90C0B6AC29AB05B3, 0x37A9A83C4E251AE6, 0x0A7DC875C2AADE7D, 0x77387DE39F0E1A84]}},
    {P256Field{limbs: [0x1E9ECC49A56C0DD7, 0xA5CFFCD846086C74, 0x8F7A1408F505AECE, 0xB37B85C0BEF0C47E]},
     P256Field{limbs: [0x3596B6E4CC0E6A8F, 0xFD6D4BBF6B388F23, 0xABA453FAC39CEF4E, 0x9C135AC8F9F628D5]}},
    {P256Field{limbs: [0x0A1C729495C8F8BE, 0x2961C4803BF362BF, 0x9E418403DF63D4AC, 0xC109F9CB91ECE900]},
     P256Field{limbs: [0xC2D095D058945705, 0xB9083D96DDEB85C0, 0x84692B8D7A40449B, 0x9BC3344F2EEE1EE1]}},
    {P256Field{limbs: [0x0D5AE35642913074, 0x55491B2748A542B1, 0x469CA665B310732A, 0x29591D525F1A4CC1]},
     P256Field{limbs: [0xE76F5B6BB84F983F, 0xBE7EEF419F5F84E1, 0x1200D49680BAA189, 0x6376551F18EF332C]}}]

private func p256MultiplyGenerator(scalar: const *P256Field)->P256Point
{
    let one    = P256Field{limbs: P256MontgomeryOne}
    var result = p256Infinity()
    for step in 64
    {
        result = p256PointDouble(result)
        let shift   = 63 - step
        let digits0 = (scalar[].limbs[0] >> shift) & 1
        let digits1 = (scalar[].limbs[1] >> shift) & 1
        let digits2 = (scalar[].limbs[2] >> shift) & 1
        let digits3 = (scalar[].limbs[3] >> shift) & 1
        let digit   = digits0 | (digits1 << 1) | (digits2 << 2) | (digits3 << 3)

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
    let curveBRaw = P256Field{limbs: [0x3BCE3C3E27D2604B, 0x651D06B0CC53B0F6, 0xB3EBBD55769886BC, 0x5AC635D8AA3A93E7]}
    let curveB    = p256ToMontgomery(curveBRaw)
    let expected  = p256FieldAdd(p256FieldSubtract(xCubed, threeX), curveB)
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
    var nonceBytes = p256Rfc6979Nonce(privateKey, messageDigest)
    defer Crypto.secureClear(Swag.makeSlice(&nonceBytes, 1))
    var nonce = try p256ScalarDecode(nonceBytes)
    defer Crypto.secureClear(Swag.makeSlice(&nonce, 1))

    var noncePoint = p256MultiplyGenerator(&nonce)
    defer Crypto.secureClear(Swag.makeSlice(&noncePoint, 1))
    var r = p256OrderReduce(p256FromMontgomery(p256AffineX(noncePoint)))
    if not p256ScalarIsValid(r) do
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid nonce"}

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
    if not p256ScalarIsValid(s) do
        fail Errors.BadParameterError{"P-256 ECDSA generated an invalid signature"}

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

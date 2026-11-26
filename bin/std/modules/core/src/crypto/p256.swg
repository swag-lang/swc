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

private func(IsField: bool) p256MontgomeryMultiply(left, right: [4] u64)->[4] u64
{
    const Modulus = IsField ? P256Modulus : P256Order
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
        #static if IsField
        {
            // The prime's least-significant word is 2^64 - 1. Its product
            // cancels word zero, with the reduction factor as the carry.
            let factor  = temporary[0]
            let shifted = factor << 32
            let word1   = temporary[1] + shifted
            let carry1  = (factor >> 32) + cast(u64, word1 < shifted)
            temporary[0] = word1

            // The middle words are 2^32 - 1 and zero. The carry from
            // word zero turns the first product into a single left shift.
            let word2  = temporary[2] + carry1
            let carry2 = cast(u64, word2 < carry1)
            temporary[1] = word2

            // The high word is 2^64 - 2^32 + 1.
            let low   = factor - shifted
            let high  = factor - (factor >> 32) - cast(u64, factor < shifted)
            let sum   = low + temporary[3]
            let word3 = sum + carry2
            temporary[2] = word3
            carry        = high + cast(u64, sum < low) + cast(u64, word3 < sum)
        }
        else
        {
            let reduction = temporary[0] * P256OrderWordInverse
            carry = p256MultiplyAdd(reduction, Modulus[0], temporary[0], 0).carry
            for word in 1 until 4
            {
                let product = p256MultiplyAdd(reduction, Modulus[word], temporary[word], carry)
                temporary[word - 1] = product.word
                carry = product.carry
            }
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
        let word = temporary[index] - Modulus[index]
        difference[index] = word - borrow
        borrow = cast(u64, temporary[index] < Modulus[index]) | cast(u64, word < borrow)
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
    result.limbs = p256MontgomeryMultiply'true(left.limbs, right.limbs)
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

// Stripe i contains multiples of [2^(16*i)]G. Entry d-1 combines
// the four scalar columns spaced by 64 bits. The zero selection is infinity.
private const P256GeneratorComb: [4][15] P256AffinePoint = [
    [{P256Field{limbs: [0x79E730D418A9143C, 0x75BA95FC5FEDB601, 0x79FB732B77622510, 0x18905F76A53755C6]},
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
      P256Field{limbs: [0xE76F5B6BB84F983F, 0xBE7EEF419F5F84E1, 0x1200D49680BAA189, 0x6376551F18EF332C]}}],
    [{P256Field{limbs: [0x0F0165FCE3779EE3, 0xE00E7F9DBD495D9E, 0x1FA4EFA220284E7A, 0x4564BADE47AC6219]},
      P256Field{limbs: [0x90E6312AC4708E8E, 0x4F5725FBA71E9ADF, 0xE95F55AE3D684B9F, 0x47F7CCB11E94B415]}},
     {P256Field{limbs: [0xE4050F1CF1C367CA, 0x9BC85A9BC90FBC7D, 0xA373C4A2E1A11032, 0xB64232B7AD0393A9]},
      P256Field{limbs: [0xF5577EB0167DAD29, 0x1604F30194B78AB2, 0x0BAA94AFE829348B, 0x77FBD8DD41654342]}},
     {P256Field{limbs: [0xF74B5EE5B65659B6, 0x58D272060DE651DE, 0x9A06F93C58635522, 0x1741DC84B51B7153]},
      P256Field{limbs: [0xD74E2F485E3B1CF2, 0x71F6A8E9F2886A41, 0x0F719872034D98F3, 0xEE792E37BCA289A6]}},
     {P256Field{limbs: [0x80531FE1C63C4962, 0x50541E89981FDB25, 0xDC1291A1FD4C2B6B, 0xC0693A17A6DF4FCA]},
      P256Field{limbs: [0xB2C4604E0117F203, 0x245F19630A99B8D0, 0xAEDC20AAC6212C44, 0xB1ED4E56520F52A8]}},
     {P256Field{limbs: [0x9DA036629673D875, 0x47C5CE723335F166, 0x24E892E354E58C2D, 0x07228F0138845A00]},
      P256Field{limbs: [0xFF9F34A22F8855A7, 0xF7D6D205C4E307FC, 0xBCD425E23455BB93, 0xD7CBB02C6D96414F]}},
     {P256Field{limbs: [0x19B3EDB45E6B555B, 0x958C797EFD18DA56, 0x22DD3354E98F9273, 0x8421223409CB54D9]},
      P256Field{limbs: [0xE39CA71D7A6402BA, 0x822D787C9378F1DE, 0xAAF852D02BEAA75D, 0xD8AF72B4510FC33A]}},
     {P256Field{limbs: [0xE4DE6BD8583F402B, 0xEDE94383B3481FDB, 0x924056D748D08E35, 0x8E349069EABD2ECC]},
      P256Field{limbs: [0x7B33363CE0D67374, 0x70E419452D8C05EB, 0xB78A5B3582D2BA0A, 0x8490D830E005D3E7]}},
     {P256Field{limbs: [0x75D9BC15ADF7CCCF, 0x81A3E5D6DFA1E1B0, 0x8C39E444249BC17E, 0xF37DCCB28EA7FD43]},
      P256Field{limbs: [0xDA654873907FBA12, 0x35DAA6DA4A372904, 0x0564CFC66283A6C5, 0xD09FA4F64A9395BF]}},
     {P256Field{limbs: [0x7B2C19D8444A73F6, 0xC88F4CE46FEEE88A, 0x9A1F7A70D431D8D2, 0xAE042119C1B25749]},
      P256Field{limbs: [0x467B64CE45B9DDF1, 0x45DF2010689F927B, 0xC874C67101D12B64, 0xC4ACA24DD4DF95FE]}},
     {P256Field{limbs: [0xC660550E732325C7, 0xD4D12681E3FE0994, 0xFFCFE8EDECFD8B7C, 0x858B5225308E65B4]},
      P256Field{limbs: [0x9523F8B4DC162423, 0x89507A8024271A6B, 0xB4D2EAF6658D58C5, 0x80E7BA28B9C205ED]}},
     {P256Field{limbs: [0x46C063953C52EBB9, 0x7333D509D02F1E43, 0x2D6B41FDB79CA51F, 0xB3B3D1DD23817A73]},
      P256Field{limbs: [0x1FDEDDB41CF976A4, 0x4BE0FC0F97B7BAC8, 0x1E638FD1A784D816, 0xFA4EAF60E439BF08]}},
     {P256Field{limbs: [0x8CB0C4AC5FCA6FF1, 0x9DA506C24B607037, 0x46E892AB0DB25734, 0x115FD8DEDFFB31B0]},
      P256Field{limbs: [0xD9135992C90EAAAE, 0xB41EEAA6EEBF8578, 0xCB24BE1E7A389C05, 0x29971D57B1809587]}},
     {P256Field{limbs: [0x078A14BA418EF20C, 0x6A4CD780824BA43D, 0xE7447778C442AC87, 0x1C472ACAD8BBA232]},
      P256Field{limbs: [0xB45C362F44237888, 0x7B2C167684EF1C00, 0x1E9F3C994500185C, 0x8122FDD0CFB13DB4]}},
     {P256Field{limbs: [0xE96E5C936EFF12E1, 0x0ABCC1DA25E31583, 0xC844E8CCDC95F5F9, 0x5A886B1B301F27CF]},
      P256Field{limbs: [0x845D7086B7B385F0, 0x8D1C658C05090238, 0xCDD1B2A62C07960B, 0xEF902DCCEE151588]}},
     {P256Field{limbs: [0x85FF4F350FEA91E5, 0x32954682AF91BDA6, 0xFE1F173D8EEAAFCA, 0x5BADAB632DA4161B]},
      P256Field{limbs: [0x2107BC51BF84E659, 0xF4368698AD86CAA0, 0x84AD8CF46E9FBE0E, 0xF7F134ADB45A2551]}}],
    [{P256Field{limbs: [0x202886024147519A, 0xD0981EAC26B372F0, 0xA9D4A7CAA785EBC8, 0xD953C50DDBDF58E9]},
      P256Field{limbs: [0x9D6361CCFD590F8F, 0x72E9626B44E6C917, 0x7FD9611022EB64CF, 0x863EBB7E9EB288F3]}},
     {P256Field{limbs: [0x4FE7EE31B0E63D34, 0xF4600572A9E54FAB, 0xC0493334D5E7B5A4, 0x8589FB9206D54831]},
      P256Field{limbs: [0xAA70F5CC6583553A, 0x0879094AE25649E5, 0xCC90450710044652, 0xEBB0696D02541C4F]}},
     {P256Field{limbs: [0xABBAA0C03B89DA99, 0xA6F2D79EB8284022, 0x27847862B81C05E8, 0x337A4B5905E54D63]},
      P256Field{limbs: [0x3C67500D21F7794A, 0x207005B77D6D7F61, 0x0A5A378104CFD6E8, 0x0D65E0D5F4C2FBD6]}},
     {P256Field{limbs: [0xD433E50F6D3549CF, 0x6F33696FFACD665E, 0x695BFDACCE11FCB4, 0x810EE252AF7C9860]},
      P256Field{limbs: [0x65450FE17159BB2C, 0xF7DFBEBE758B357B, 0x2B057E74D69FEA72, 0xD485717A92731745]}},
     {P256Field{limbs: [0xCE1F69BBE83F7669, 0x09F8AE8272877D6B, 0x9548AE543244278D, 0x207755DEE3C2C19C]},
      P256Field{limbs: [0x87BD61D96FEF1945, 0x18813CEFB12D28C3, 0x9FBCD1D672DF64AA, 0x48DC5EE57154B00D]}},
     {P256Field{limbs: [0xEF0F469EF49A3154, 0x3E85A5956E2B2E9A, 0x45AAEC1EAA924A9C, 0xAA12DFC8A09E4719]},
      P256Field{limbs: [0x26F272274DF69F1D, 0xE0E4C82CA2FF5E73, 0xB9D8CE73B7A9DD44, 0x6C036E73E48CA901]}},
     {P256Field{limbs: [0xE1E421E1A47153F0, 0xB86C3B79920418C9, 0x93BDCE87705D7672, 0xF25AE793CAB79A77]},
      P256Field{limbs: [0x1F3194A36D869D0C, 0x9D55C8824986C264, 0x49FB5EA3096E945E, 0x39B8E65313DB0A3E]}},
     {P256Field{limbs: [0xE3417BC035D0B34A, 0x440B386B8327C0A7, 0x8FB7262DAC0362D1, 0x2C41114CE0CDF943]},
      P256Field{limbs: [0x2BA5CEF1AD95A0B1, 0xC09B37A867D54362, 0x26D6CDD201E486C9, 0x20477ABF42FF9297]}},
     {P256Field{limbs: [0x0F121B41BC0A67D2, 0x62D4760A444D248A, 0x0E044F1D659B4737, 0x08FDE365250BB4A8]},
      P256Field{limbs: [0xACEEC3DA848BF287, 0xC2A62182D3369D6E, 0x3582DFDC92449482, 0x2F7E2FD2565D6CD7]}},
     {P256Field{limbs: [0x0A0122B5178A876B, 0x51FF96FF085104B4, 0x050B31AB14F29F76, 0x84ABB28B5F87D4E6]},
      P256Field{limbs: [0xD5ED439F8270790A, 0x2D6CB59D85E3F46B, 0x75F55C1B6C1E2212, 0xE5436F6717655640]}},
     {P256Field{limbs: [0xC2965ECC9AEB596D, 0x01EA03E7023C92B4, 0x4704B4B62E013961, 0x0CA8FD3F905EA367]},
      P256Field{limbs: [0x92523A42551B2B61, 0x1EB7A89C390FCD06, 0xE7F1D2BE0392A63E, 0x96DCA2644DDB0C33]}},
     {P256Field{limbs: [0x231C210E15339848, 0xE87A28E870778C8D, 0x9D1DE6616956E170, 0x4AC3C9382BB09C0B]},
      P256Field{limbs: [0x19BE05516998987D, 0x8B2376C4AE09F4D6, 0x1DE0B7651A3F933D, 0x380D94C7E39705F4]}},
     {P256Field{limbs: [0x3685954B8C31C31D, 0x68533D005BF21A0C, 0x0BD7626E75C79EC9, 0xCA17754742C69D54]},
      P256Field{limbs: [0xCC6EDAFFF6D2DBB2, 0xFD0D8CBD174A9D18, 0x875E8793AA4578E8, 0xA976A7139CAB2CE6]}},
     {P256Field{limbs: [0xCE37AB11B43EA1DB, 0x0A7FF1A95259D292, 0x851B02218F84F186, 0xA7222BEADEFAAD13]},
      P256Field{limbs: [0xA2AC78EC2B0A9144, 0x5A024051F2FA59C5, 0x91D1ECA56147CE38, 0xBE94D523BC2AC690]}},
     {P256Field{limbs: [0x2D8DAEFD79EC1A0F, 0x3BBCD6FDCEB39C97, 0xF5575FFC58F61A95, 0xDBD986C4ADF7B420]},
      P256Field{limbs: [0x81AA881415F39EB7, 0x6EE2FCF5B98D976C, 0x5465475DCF2F717D, 0x8E24D3C46860BBD0]}}],
    [{P256Field{limbs: [0xCC7A64880A750C0F, 0x39BACFE34E548E83, 0x3D418C760C110F05, 0x3E4DAA4CB1F11588]},
      P256Field{limbs: [0x2733E7B55FFC69FF, 0x46F147BC92053127, 0x885B2434D722DF94, 0x6A444F65E6FC6B7C]}},
     {P256Field{limbs: [0x8CE9B6BFC360E25A, 0xE6425195075A1A78, 0x9DC756A8481732F4, 0x83C0440F5432B57A]},
      P256Field{limbs: [0xC670B3F1D720281F, 0x2205910ED135E051, 0xDED14B0EDB052BE7, 0x697B3D27C568EA39]}},
     {P256Field{limbs: [0x4516B5B8B7881C8B, 0xCFE743C69A5825B4, 0x3D5B8B06C24E3024, 0x31C1A413CF8C9326]},
      P256Field{limbs: [0x5E6EEE84B632AE3B, 0xDFB7EB6B2BD48B14, 0x6A6515299A7261E9, 0x996B358DAA69133C]}},
     {P256Field{limbs: [0xB81D783E979F3925, 0x1EFD130AAF4C89A7, 0x525C2144FD1BF7FA, 0x4B2969041B265A9E]},
      P256Field{limbs: [0xED8E9634B9DB65B6, 0x35C82E3203599D8A, 0xDAA7A54F403563F3, 0x9DF088AD022C38AB]}},
     {P256Field{limbs: [0x396B8D047025AA01, 0xA98B2CE9E23E9595, 0x9769E7C820BB29F4, 0x23778EBB201A51A5]},
      P256Field{limbs: [0x653FF433A9B810A4, 0x017773DC66F269A7, 0xBCE2AE82129AE800, 0x3234515151317D6B]}},
     {P256Field{limbs: [0x39A3BD51F67A99FA, 0x63441F7CBA72C87F, 0xCC3FC76F745125CA, 0x670E00C69C686D78]},
      P256Field{limbs: [0xA35C29F9A0277D6D, 0x078BADCF3E443178, 0x1CA01D3F5D1C6E16, 0x23751C99FC8934CF]}},
     {P256Field{limbs: [0x907C4F80EC245C99, 0xA8943D3316273128, 0x8984E2CB2E233AE1, 0x655A4DDA794C6256]},
      P256Field{limbs: [0x88E95CE7EE6E1497, 0x977F927F129D3376, 0x2758787A568A3FF3, 0x0BDF684FDC3CBCE1]}},
     {P256Field{limbs: [0x1083E2EA1F095615, 0x0A28AD7714E68C33, 0x6BFC02523D8818BE, 0xB585113AF35850CD]},
      P256Field{limbs: [0x7D935F0B30DF8AA1, 0xADDDA07C4AB7E3AC, 0x92C34299552F00CB, 0xC33ED1DE2909DF6C]}},
     {P256Field{limbs: [0x222C4A8A10FB29B2, 0x5508658630B7EB36, 0x22D15C091EE898A1, 0xB4A70D45854090DE]},
      P256Field{limbs: [0x3BE7A3896F61FBDC, 0xA7D262AFFD3348C4, 0x9682EC29E66D5552, 0x5EF177EA14CBB8D6]}},
     {P256Field{limbs: [0x3067F7937EAFB650, 0xE37DFBF43BF2A0CB, 0xE6B8E19A8C3AC824, 0x8C4930BFA05E8B4B]},
      P256Field{limbs: [0xD691267645CDB7BC, 0xCEBDCE5705EA892C, 0xF00C54038015170F, 0x2E12DFCC7B65A3E5]}},
     {P256Field{limbs: [0x9BDFC7A96C5F67D0, 0x64A44BE0986471A7, 0x7F12C705B721ACA9, 0xCC2F523CD760D701]},
      P256Field{limbs: [0x49BB9288B46FEBF2, 0x6A207099375964E6, 0x6CA4A4990420792F, 0x2188C12D38BCA9E8]}},
     {P256Field{limbs: [0x3857F5C48EE50F1E, 0xF8F801D209A578E4, 0xBE6C89FDF20F170E, 0x5BA08B2FABCF2FA9]},
      P256Field{limbs: [0x86803B77486F3CFC, 0x846A92F79CF883EA, 0xBFB52676474FEB56, 0x483127B0D252161A]}},
     {P256Field{limbs: [0x18288CFE6A658C2B, 0xE9EAEF2D0B3D9E91, 0x58F2023F9AE474F2, 0x0BDAE4B1BCF34170]},
      P256Field{limbs: [0x9B725D7BB1861D12, 0x2BC04F740B4725BB, 0xD9FE2C7CD2AEFC19, 0x5E985BB6610B818E]}},
     {P256Field{limbs: [0x58B1117CB4998E4B, 0xA2CCC539EE2B2E32, 0x5D1033E8127F3F60, 0x6958923BBBC4B91D]},
      P256Field{limbs: [0xA077A0CF70AA136D, 0xD2FA8875641BBF55, 0x74D271AA32837130, 0xFE89C10033C1D7BF]}},
     {P256Field{limbs: [0x8DE0880532237E81, 0xF43684EC874DFAEE, 0xFDBA26B988BEF633, 0xAC2994045D2A9C91]},
      P256Field{limbs: [0xEEA6A5A0A96659E1, 0xE74A555DD25EC31A, 0x8663B8F1D7D5A482, 0x50B490D71B5845E4]}}]]

private func p256MultiplyGenerator(scalar: const *P256Field)->P256Point
{
    const Steps = 16
    let one    = P256Field{limbs: P256MontgomeryOne}
    var result = p256Infinity()
    for step in Steps
    {
        result = p256PointDouble(result)
        for stripe in P256GeneratorComb.count
        {
            let shift   = Steps - 1 - step + stripe * Steps
            let digits0 = (scalar[].limbs[0] >> shift) & 1
            let digits1 = (scalar[].limbs[1] >> shift) & 1
            let digits2 = (scalar[].limbs[2] >> shift) & 1
            let digits3 = (scalar[].limbs[3] >> shift) & 1
            let digit   = digits0 | (digits1 << 1) | (digits2 << 2) | (digits3 << 3)

            var selection: P256Point
            for index in P256GeneratorComb[stripe].count
            {
                let matched = index + 1 == digit
                let point   = P256GeneratorComb[stripe][index]
                selection.x = p256FieldSelect(selection.x, point.x, matched)
                selection.y = p256FieldSelect(selection.y, point.y, matched)
            }

            selection.z = p256FieldSelect(P256Field{}, one, digit != 0)
            var doubled = p256PointDouble(result)
            result = p256PointAddAffine(result, selection, doubled)
            Crypto.secureClear(Swag.makeSlice(&selection, 1))
            Crypto.secureClear(Swag.makeSlice(&doubled, 1))
        }
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

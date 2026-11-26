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

    // These local words are aligned. Atomic stores survive dead-store elimination.
    for word in 4
    {
        Swag.atomicStore(&temporary[word], 0)
        Swag.atomicStore(&difference[word], 0)
    }

    Swag.atomicStore(&temporary[4], 0)
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
    let mask = Math.Simd.splat(0'u64 - cast(u64, selectRight))
    var result: #returntype
    for pair in 2
    {
        let index = pair * 2
        let first = Math.Simd.load(left.limbs.buffer + index)
        let second = Math.Simd.load(right.limbs.buffer + index)
        Math.Simd.store(result.limbs.buffer + index, first ^ ((first ^ second) & mask))
    }

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
    x: P256Field
    y: P256Field
}

// Each stripe uses signed columns spaced by 64 bits. The eight entries
// have a positive highest column. Negation covers the other signs.
private const P256GeneratorComb: [8][8] P256AffinePoint = [
    [{P256Field{limbs: [0x52D8A7C9670844E0, 0x00E33BDCEF68A29D, 0x0F3D28484BDB7361, 0x5222C82191C5304D]},
      P256Field{limbs: [0xEA6D2944DF73FC25, 0xA04C0F550255C81B, 0x29ACDC97EFE488A8, 0xBE2E158F80A560DE]}},
     {P256Field{limbs: [0xFC8511EE2B13E673, 0xFFC58DEED103ED24, 0x1022523AEA7E99B8, 0x8F43EA394AFC8A17]},
      P256Field{limbs: [0x8F4E2DBCC5F33D0B, 0x3BC099FAD0AA1681, 0xFFBB7B4179FF9DF1, 0x180DE09DD58B57C4]}},
     {P256Field{limbs: [0x564307528BD1CDA5, 0x1807577F8E05EDA5, 0x099C699B956896E9, 0x83D6093DF1F0EFB5]},
      P256Field{limbs: [0xEF5AF17EED97061C, 0x35B977B8030D4C3C, 0x81FA75A249229439, 0xF5A22070A0B6D35D]}},
     {P256Field{limbs: [0x814C536574F81CF1, 0xE30BAFF70120065B, 0x80AE125615132621, 0x16D2B8CB36A80788]},
      P256Field{limbs: [0x33D14697ECC50BCA, 0x19A9DFB017AEDD21, 0x523FBCC7EDC3F766, 0x9C4DE6DDB2CF5AFD]}},
     {P256Field{limbs: [0x5305A9E6CF0D9F6D, 0x5839172F81A9B021, 0xCCA7A4DD75C687CF, 0x36D59B3E844BE22F]},
      P256Field{limbs: [0xCACE7E62111A53E9, 0x91C843D4F063F3A1, 0xBF77E5F00DA812DA, 0x0E64AF9C437F3176]}},
     {P256Field{limbs: [0xDBD568BBCF07517D, 0x2F1AFBA2BA6830B9, 0x15B6807CE6C4C2A6, 0x91C7EABCE4966AEF]},
      P256Field{limbs: [0x716DEA1BD6B2B6E6, 0x248C43D119F85B4B, 0x16DCFD604A315E2A, 0x15FDD303C72B3D0B]}},
     {P256Field{limbs: [0xE40BF9F442B7DFD5, 0x673689F32D934F2A, 0x8314BEB430A6F50B, 0xD17AF2BC976EC64E]},
      P256Field{limbs: [0x39F66C4F1EE7DDF1, 0x7F68E18B68EA373C, 0x5166C1F253D0B186, 0x95DDA6017BE58F14]}},
     {P256Field{limbs: [0x0D5AE35642913074, 0x55491B2748A542B1, 0x469CA665B310732A, 0x29591D525F1A4CC1]},
      P256Field{limbs: [0xE76F5B6BB84F983F, 0xBE7EEF419F5F84E1, 0x1200D49680BAA189, 0x6376551F18EF332C]}}],
    [{P256Field{limbs: [0x46F854FD9E082A81, 0x9DD1021A715DBAC6, 0x67E8DA44EBE41989, 0xDF9003A6FF6A3235]},
      P256Field{limbs: [0x35B8FEACEC7E7F35, 0xEE45ED6076395A83, 0x211B344EAE6FCE90, 0x7C8790FE6EE12BDE]}},
     {P256Field{limbs: [0x98049E4E3EDFCF09, 0x919B30CB64181986, 0x56776DF2E08A3279, 0x222617C47AE8D762]},
      P256Field{limbs: [0x7D7C6FAA9D94169E, 0x2CFC046B8C40D3FB, 0x13895C95BB1A6A24, 0xA9C08992E97C0BA0]}},
     {P256Field{limbs: [0x4F8EF895DC1C2D31, 0xFBC9172662D9677C, 0x76A3B12F681A935E, 0xBDB2804DB875E29F]},
      P256Field{limbs: [0xAB32245471BF8554, 0xADBEB2F01213207C, 0x7936B51B697E8CDC, 0x9BD05EFC5FB41150]}},
     {P256Field{limbs: [0x04C931238057CCA1, 0x413F0F23BE89C98C, 0xAB53079D03A3F5E1, 0xEAFFD9A574AE47FF]},
      P256Field{limbs: [0x0DBAA2EC810B5A31, 0xD0396F4D79A97247, 0xCBCDBE19169AA230, 0x2B4AA27EBE8BEE16]}},
     {P256Field{limbs: [0x191537F14EF6B9CA, 0x6814F084E8889D0D, 0x4E1173F9A6D7ECCD, 0x3DB55F19FC2C75A9]},
      P256Field{limbs: [0x90571329F4806696, 0x9F984E0E9998CB4C, 0x9881D2C5D848EE44, 0x98914E45E0DEF8EC]}},
     {P256Field{limbs: [0x8E95735A5E67BE83, 0x29299E733CA2C26F, 0x878F793EE8BF0E1D, 0xA7129B3E8A0E71B3]},
      P256Field{limbs: [0x3B2CE4D0CB615159, 0x7F64F020F1E33662, 0xAD41222FFE55B539, 0x1F21FAD06ED8726F]}},
     {P256Field{limbs: [0x5D3C1ED1631E756B, 0xDF2A16C354B6A1BA, 0xA4E3CBABE7078722, 0x47686E2DFA5CBE02]},
      P256Field{limbs: [0xA469A3F36E453742, 0xA1B429C909E6122A, 0x08497EF8C7E1FA0B, 0x190B9FDFA6BF6868]}},
     {P256Field{limbs: [0xF95684F7FC2B4E00, 0x114521ACEF571F04, 0x48D9B5EA4ABB78E3, 0x3DF9C7BADA9891D8]},
      P256Field{limbs: [0x1CA68374944CAB81, 0x98453F5B76FDB53F, 0x995789B8B1CD8A0E, 0xAFE5E48EE42CE845]}}],
    [{P256Field{limbs: [0x716A131BA0CF2A60, 0xC4B28B8FD73E9F7F, 0x9D701E9FECDA039B, 0x5A53BCE0113BE564]},
      P256Field{limbs: [0x81D8E13C2C6A1A74, 0x20AD31765FAB4DED, 0xD2DFDD9EBE1F317F, 0x72C479AE3F203408]}},
     {P256Field{limbs: [0x061E8041A271449A, 0x90DEBEBDBEE25A60, 0x43879D6E980A84C2, 0x474895C9120732A4]},
      P256Field{limbs: [0x93866F316F733BD9, 0x0AE4FE2A98D57052, 0x37C4C75445C3A453, 0x55BE778C885FD2C7]}},
     {P256Field{limbs: [0xA95FA0A921E72751, 0x1A21825B5FB0F501, 0xD62D8DE424A58594, 0xD328E53A5C5426B6]},
      P256Field{limbs: [0xD29204E6A6D77759, 0x58202B2970F63559, 0x5CB708741A588728, 0x7A29168593835D5A]}},
     {P256Field{limbs: [0xF46E58C17206CFA7, 0x48019F8FACC7943A, 0x72C32BD57C51ADC3, 0x12337F5FEB447CE7]},
      P256Field{limbs: [0x74CF7363E140D79E, 0x2798FC68CB11ECBD, 0xF1A1FD5D56A57C37, 0x0CC2AC48FD25E4A2]}},
     {P256Field{limbs: [0xECD440EEC7EF418D, 0x40C311768B0DB916, 0x6A16C02845FA643D, 0xE845E7CE088DA48A]},
      P256Field{limbs: [0x746270A22B9C8597, 0x7243751E7D9BCCA0, 0x6EBA4E1FF9F1AF57, 0x27AC551E6E4F3702]}},
     {P256Field{limbs: [0xF7F7A33BD6AE07B0, 0xD2973A8CA71F4BA0, 0x945E2405775DAD7A, 0x836C634C28799154]},
      P256Field{limbs: [0xBBE69C99D542F1F9, 0xD55202075942E376, 0x298D569348E3BEB0, 0x41C8BE29946E17FD]}},
     {P256Field{limbs: [0xBFCB94971145F5E1, 0x482B3B450B15FB95, 0x1B8D3B1F54165CA2, 0xB4DDB9E56E4906CB]},
      P256Field{limbs: [0xF4E2C2117EED1F05, 0xC6F02CB7F08CC5D0, 0xE80620BF76DCDEB8, 0x1A6484C99578CC66]}},
     {P256Field{limbs: [0x85FF4F350FEA91E5, 0x32954682AF91BDA6, 0xFE1F173D8EEAAFCA, 0x5BADAB632DA4161B]},
      P256Field{limbs: [0x2107BC51BF84E659, 0xF4368698AD86CAA0, 0x84AD8CF46E9FBE0E, 0xF7F134ADB45A2551]}}],
    [{P256Field{limbs: [0xAD90249E0D8663CC, 0x010D85CDFEE9CF9A, 0xE0F6962B43671CC9, 0xF0302CE82A1FA2A3]},
      P256Field{limbs: [0xE64B02C93352ADAD, 0xB91475676C542133, 0x46F67DDF74377386, 0xB0B4CC079A01C061]}},
     {P256Field{limbs: [0x9DED8DD69F3866E7, 0x87B1122EA5D85C40, 0x6E5F9FCBF65119CD, 0x3AEB0E43C329C544]},
      P256Field{limbs: [0x908B8193F04B0EAA, 0xFECD4F31A773717A, 0x6D77D12E34802F1A, 0x8A8677C8B41DFD35]}},
     {P256Field{limbs: [0x8ACC067F650050E5, 0x854CFCFD90774B85, 0x7D0A28695A50BEBE, 0x18BB26FE2103B87F]},
      P256Field{limbs: [0xBE46F8E1615B0FE8, 0xD91B49CC7579E67C, 0xC7893CBEFBCB3E13, 0x3B33BFF6408CC627]}},
     {P256Field{limbs: [0xC57ADE30C9966B30, 0xAFF64CAF7329360B, 0xA3E14295142C0ECC, 0x17D5F5EA557FB857]},
      P256Field{limbs: [0xDF930851DE290561, 0xF62497A32F61FE61, 0x353075D745F1869B, 0xF74C636C9BE5D4AB]}},
     {P256Field{limbs: [0x0CDBFEAE8D02BF56, 0xECC8A6DECD3EB0E6, 0xCFC37864D85C5F47, 0x491841E542E9B78B]},
      P256Field{limbs: [0xD7C65790B7394AD2, 0x8036AFC2B935E459, 0x293CE02C6A66A491, 0xC7AD56546C8CC205]}},
     {P256Field{limbs: [0x4A19DBA5D26D3997, 0x65CFB89B53352A05, 0x7B99F4A08259A9BF, 0x483587CE665347EC]},
      P256Field{limbs: [0xC0B144B6B0747813, 0x4398CDFFF8D7A63A, 0x7CB892A9541C6C8B, 0xB256BFAB7F52010A]}},
     {P256Field{limbs: [0xC517FE72D87D624C, 0x15CA5BE5819E1AD9, 0xC6E6AF63F265FD05, 0x008016785DD78B13]},
      P256Field{limbs: [0x6496B79EC1F16D06, 0x7840BC7944E2A635, 0x42493826DEDDF768, 0x92668133CC9BDB65]}},
     {P256Field{limbs: [0x0ED883101610CD52, 0x0DA4DC01236A1040, 0x427CA1F2924A7203, 0xA4737B77AAFD3D7D]},
      P256Field{limbs: [0x6627522096A5BA97, 0x87C057437EE66858, 0xAEB7CE8837DA5D39, 0xEE946502D4AE3B19]}}],
    [{P256Field{limbs: [0xB9E5CBC07C4E54F5, 0xC53A1A17E1410E34, 0x3E199130EC454425, 0xB029C97E1700902E]},
      P256Field{limbs: [0x2DE66E11786423B6, 0x262DC914B41A95BE, 0x51766ABD0451B683, 0x55AD5F3485BB6FB1]}},
     {P256Field{limbs: [0x074F4F1C9066CB79, 0x1AB31BD630C8B94E, 0x6D3F012FD74275B3, 0xA214D0B19DDCCE40]},
      P256Field{limbs: [0x24AEDF74D165050A, 0x95F17ECEE0E5DC3E, 0x6ADA9CDAD9224456, 0x1FADB2D12DD60EEA]}},
     {P256Field{limbs: [0xA3D83091E20CFB9B, 0xAE79C975BA76E0CB, 0xA5F2A588C8858A6E, 0xE897A5F4874A3168]},
      P256Field{limbs: [0xF6C1EF407D48F096, 0x1F9C516BC35B132C, 0xE1040F9153C479FD, 0x060E881F9DF06743]}},
     {P256Field{limbs: [0x09E0AD7252A90E51, 0xB7E66EA338C50A96, 0xAB32AD057D997770, 0x0CEAFFE2445671CB]},
      P256Field{limbs: [0xDFBE753C5D37CC99, 0x95D068CCE0FEA2D5, 0x1E37CDDA4DD77CB6, 0x88C5A4BB55530688]}},
     {P256Field{limbs: [0x3413F0330C7744F1, 0x23C05C89BC816702, 0x2322EE9A1192B5AC, 0x0C1636A0373180BB]},
      P256Field{limbs: [0x0FE2F3D4BDDE0207, 0x0E1A093AC23578D8, 0x06E5F0D10C888EAD, 0x9CA285A552A2B660]}},
     {P256Field{limbs: [0xDAE76995CE923964, 0xCC96493AA34C7993, 0xD19B5144EA73D9E7, 0x04A5C263311E6E34]},
      P256Field{limbs: [0x7DB5B32BD9A2A443, 0x3754BD332CFD960C, 0x0C5BCC980A430F15, 0x5651201FD9A94574]}},
     {P256Field{limbs: [0xEBDD8921FC0418FE, 0x37015B3934E20036, 0xCF4FCD8FDF03A353, 0xDC2DE6E1F12CAB16]},
      P256Field{limbs: [0x9C17CC1AD071DF14, 0xD7C5E6A363415530, 0xB530166068F3FB1E, 0xB5F70BC918269301]}},
     {P256Field{limbs: [0x2D8DAEFD79EC1A0F, 0x3BBCD6FDCEB39C97, 0xF5575FFC58F61A95, 0xDBD986C4ADF7B420]},
      P256Field{limbs: [0x81AA881415F39EB7, 0x6EE2FCF5B98D976C, 0x5465475DCF2F717D, 0x8E24D3C46860BBD0]}}],
    [{P256Field{limbs: [0x9AC68E8AA06383FA, 0xD4B8C399AEBD7360, 0x153A92538B304987, 0x27F30D4F2BF3B560]},
      P256Field{limbs: [0xAE00B21556F7D761, 0x54AEB406E2D5A6E0, 0x20081DAF1BD5F230, 0x0D625B7B43EF01A3]}},
     {P256Field{limbs: [0x8A2F93E1C2688D91, 0xA1446DA87196E817, 0x262A18BBF21A0E9B, 0x48A2C8A00C2C916B]},
      P256Field{limbs: [0xEEDF3B53221D2F4C, 0x8522EB14CF72DB92, 0x1FA89B530D4A963F, 0xD46681B2978B8A61]}},
     {P256Field{limbs: [0x0B62EE1D33968D53, 0x3EE356122AEC9108, 0xB7C07A8279675936, 0x303D3A0E9031A745]},
      P256Field{limbs: [0x024622192A4F2B1F, 0x5D85E01C0A5CBB50, 0x1382884A6053FD99, 0x7BBAD6A8DE960F0C]}},
     {P256Field{limbs: [0x7F9E418F094CB56F, 0x58517960B465EFD0, 0xCF33CBDA24C18E1D, 0x6F9DEB23C0BAF52A]},
      P256Field{limbs: [0xBA72F95C0CFC63C2, 0x529C7A01E268B866, 0x2D716F12D2E668C5, 0xC6F6D7A2D8CF0B0F]}},
     {P256Field{limbs: [0x51824670EC10342F, 0x5D08CF4952C2A183, 0xAF6A4ED2830E1806, 0x40EE181DBEC885F9]},
      P256Field{limbs: [0x7C4A74AFC1D9E055, 0xE689D6478504A968, 0xCAC18384F9A1B90D, 0x1CD8045E3DD252E9]}},
     {P256Field{limbs: [0x5C8AA2E38A563CF2, 0xB9946BCFF320D88D, 0x2B7B8E1094C44265, 0x07A8015BDAC53E97]},
      P256Field{limbs: [0xCF1FBAF4B00AB40A, 0x5A5006FD507717D3, 0x7FF8D6ED68EB735D, 0x8A03E1EA713F846A]}},
     {P256Field{limbs: [0x29354FECAB169F6C, 0x0449CBC9BCC7DDAC, 0x6AB17FA224377583, 0x34130C2C7F9E0AB2]},
      P256Field{limbs: [0x715BA5DAA53DA9CB, 0x1AF6F4CF844F48F1, 0xB0BABED0B7CC43AB, 0x387AA6EB1CCF3C29]}},
     {P256Field{limbs: [0xBFCA3418B2630DE5, 0xDB52A23086980A16, 0x732A1969128DD83A, 0x38193F06B3F0C36E]},
      P256Field{limbs: [0xDEF6B620A449A0EF, 0xF2AA561569F5DE63, 0x87325C3C77945DF2, 0xE088927630E90C8D]}}],
    [{P256Field{limbs: [0x349D63FE74B3B2B5, 0x0455FFFFE3643FDA, 0x13078808B5554B65, 0x706178287AEF08A2]},
      P256Field{limbs: [0xBA1224844B19CB81, 0xA14D037B9EC65BB4, 0x5B48EF683E95E388, 0x8B773836A9B3EC25]}},
     {P256Field{limbs: [0xFB69EA682FE5B0C0, 0x11411E2728AE8EAD, 0x46F7861A22A17FA4, 0x2D46E9898E0A2B46]},
      P256Field{limbs: [0x477DA4C29E09F032, 0x3BA21660FC369ACD, 0xC8699CC67B689343, 0x603F81770894EFFF]}},
     {P256Field{limbs: [0x6D94D5B39A053AE6, 0x2EF99DA1B34174E5, 0xF23D766A1CD3C6A5, 0xC0A94B4AC3BFC938]},
      P256Field{limbs: [0x2CF2038E7527A76D, 0x114F7164F82ECB1A, 0x1C74AF3BF8CDFCF5, 0x10295C08314D984D]}},
     {P256Field{limbs: [0xBE0DEE24D6D17EBF, 0x745C4CA74B22A7F7, 0x5E2BDA17692980D4, 0xDC04A3FAA522844E]},
      P256Field{limbs: [0x960D7DA9E72FD0CD, 0xCA50BB854C79A612, 0x4E75E17CA34C6590, 0xDA0A7BBFBD21D868]}},
     {P256Field{limbs: [0xAA0E7E8EA32A3534, 0x35989737EEE98CA9, 0x3E6B57442B24FB98, 0x4171B92A1C036833]},
      P256Field{limbs: [0x24CEEA7504CE6029, 0x2F9288D8247378CF, 0xFF80915676738CF7, 0xD4CEA73C7A393C21]}},
     {P256Field{limbs: [0xA33282E28F7AFB46, 0x81410B2CAE457EE9, 0xB23D45CBB94F9DEF, 0x03D1533EB0426903]},
      P256Field{limbs: [0x539C2D8F26071972, 0xD993EE4F9C939F4F, 0x309BFAE09598D171, 0x509A4FC9B4379E17]}},
     {P256Field{limbs: [0x52D6DCC535B74EC6, 0x2B6FF7C952CEAF16, 0x5343F9952F906ED7, 0x3EA6BAB03E298B6A]},
      P256Field{limbs: [0x9BE35AC25B08AA26, 0x1307A29B6D8B0592, 0x09F4C192ED88F422, 0x8877E81FA3FE4249]}},
     {P256Field{limbs: [0x8DE0880532237E81, 0xF43684EC874DFAEE, 0xFDBA26B988BEF633, 0xAC2994045D2A9C91]},
      P256Field{limbs: [0xEEA6A5A0A96659E1, 0xE74A555DD25EC31A, 0x8663B8F1D7D5A482, 0x50B490D71B5845E4]}}],
    [{P256Field{limbs: [0x9869BE543FA22429, 0x5E52255CBBF78F63, 0x9C1DBBE94E24090E, 0xD165C5748A64F78A]},
      P256Field{limbs: [0xE686601DCF5480CE, 0x9B58FE722AEE181D, 0xD4076B8CE7C83ABF, 0x65F73D730D4B8243]}},
     {P256Field{limbs: [0xC0B53540545590F9, 0x9CBE9F3F762B3362, 0x017E3BA8BAAEA52F, 0x91E9FC11F4CF95A0]},
      P256Field{limbs: [0xA60667CDDB8CD55E, 0x7688C370EA3935B7, 0xDF95B1168C786C62, 0x4CB4A0986E76ADB1]}},
     {P256Field{limbs: [0x38D18AD1064FF6EB, 0xE3D9D02EBF7D1595, 0xD9B7B13CF77BCFA6, 0xFD73A945A1111A33]},
      P256Field{limbs: [0x17A7145840EA70F1, 0xC18EB84D58F46306, 0x345A99F2E78DFCE8, 0x8A9034E96F7F41D3]}},
     {P256Field{limbs: [0xC06C2221E24343DC, 0x2BDAFE82D17DB1E9, 0x6F567D0E38E05228, 0x3121E245DB89FC30]},
      P256Field{limbs: [0x1786B0F17E51EA7C, 0xB18455C13F28A2D2, 0xE0F57C3132C9B213, 0x1783EF6A9C654649]}},
     {P256Field{limbs: [0x7E4957AD7BAD7CB8, 0xFE0E56F0C0A7F69E, 0x106C90C2D5FF9935, 0xBDD075747DF182AF]},
      P256Field{limbs: [0xC6714C1B8B8CDF77, 0x4A8EBFB6A4D35B1B, 0xF89B5906E2B8698A, 0x2B271A08D65FEE09]}},
     {P256Field{limbs: [0x66A0E646E84087B3, 0xA36EE17C16E17B57, 0x13D12BFE10FE35FE, 0x00E7AE320DE3D428]},
      P256Field{limbs: [0x290ECC3716AEB17E, 0x9A8E7CD423C04210, 0x62A37DB3B05566A0, 0x18B59474DAB78BCA]}},
     {P256Field{limbs: [0x5A65BC691A7036B0, 0x2A8C78A8046E8365, 0x26E27CB42EFEB635, 0xAA88289972D244B3]},
      P256Field{limbs: [0xEB73724922406E08, 0x7B1DFBF3DDA1DC6C, 0x9DAA7156779DBDE7, 0xB399596C7E8E404F]}},
     {P256Field{limbs: [0xDE4CF2BE00E29B03, 0xDC38C4E35BF6B853, 0x4AF556A862B93D98, 0x493F4823A4E5DB9D]},
      P256Field{limbs: [0x4BF133B6C3FCC6CC, 0xB83ECD49BCD26660, 0x313C78B6F9B56B20, 0x92C4010E1715E3B2]}}]]

// Homogeneous projective coordinates use (X/Z, Y/Z).
private struct P256HomogeneousPoint
{
    x: P256Field
    y: P256Field
    z: P256Field
}

private const P256MontgomeryB = P256Field{limbs: [0xD89CDF6229C4BDDF, 0xACF005CD78843090, 0xE5A220ABF7212ED6, 0xDC30061D04874834]}

#[Swag.Inline]
private func p256HomogeneousToJacobian(point: P256HomogeneousPoint)->P256Point
{
    return {x: p256FieldMultiply(point.x, point.z),
            y: p256FieldMultiply(point.y, p256FieldSquare(point.z)),
            z: point.z}
}

#[Swag.Inline]
private func p256HomogeneousFinishAdd(xx, yy, zz, xy, yz, xz: P256Field)->P256HomogeneousPoint
{
    let mixedZ = p256FieldTriple(p256FieldSubtract(xz, p256FieldMultiply(P256MontgomeryB, zz)))
    let upper  = p256FieldAdd(yy, mixedZ)
    let lower  = p256FieldSubtract(yy, mixedZ)
    let scaledXZ = p256FieldTriple(p256FieldSubtract(p256FieldSubtract(p256FieldMultiply(P256MontgomeryB, xz), p256FieldTriple(zz)), xx))
    let scaledXX = p256FieldTriple(p256FieldSubtract(xx, zz))

    return {x: p256FieldSubtract(p256FieldMultiply(xy, upper), p256FieldMultiply(yz, scaledXZ)),
            y: p256FieldAdd(p256FieldMultiply(upper, lower), p256FieldMultiply(scaledXX, scaledXZ)),
            z: p256FieldAdd(p256FieldMultiply(yz, lower), p256FieldMultiply(xy, scaledXX))}
}

// The unified mixed addition of Renes, Costello and Batina uses a finite
// affine second point and also handles coincident and opposite points.
private func p256HomogeneousAdd(point: P256HomogeneousPoint, affine: P256AffinePoint)->P256HomogeneousPoint
{
    let xx = p256FieldMultiply(point.x, affine.x)
    let yy = p256FieldMultiply(point.y, affine.y)
    let xy = p256FieldSubtract(p256FieldMultiply(p256FieldAdd(point.x, point.y), p256FieldAdd(affine.x, affine.y)), p256FieldAdd(xx, yy))
    let yz = p256FieldAdd(p256FieldMultiply(affine.y, point.z), point.y)
    let xz = p256FieldAdd(p256FieldMultiply(affine.x, point.z), point.x)
    return p256HomogeneousFinishAdd(xx, yy, point.z, xy, yz, xz)
}

// Both operands are valid homogeneous points, including infinity.
private func p256HomogeneousAddProjective(left, right: P256HomogeneousPoint)->P256HomogeneousPoint
{
    let xx = p256FieldMultiply(left.x, right.x)
    let yy = p256FieldMultiply(left.y, right.y)
    let zz = p256FieldMultiply(left.z, right.z)
    let xy = p256FieldSubtract(p256FieldMultiply(p256FieldAdd(left.x, left.y), p256FieldAdd(right.x, right.y)), p256FieldAdd(xx, yy))
    let yz = p256FieldSubtract(p256FieldMultiply(p256FieldAdd(left.y, left.z), p256FieldAdd(right.y, right.z)), p256FieldAdd(yy, zz))
    let xz = p256FieldSubtract(p256FieldMultiply(p256FieldAdd(left.x, left.z), p256FieldAdd(right.x, right.z)), p256FieldAdd(xx, zz))
    return p256HomogeneousFinishAdd(xx, yy, zz, xy, yz, xz)
}

private func p256HomogeneousDouble(point: P256HomogeneousPoint)->P256HomogeneousPoint
{
    let w = p256FieldTriple(p256FieldMultiply(p256FieldSubtract(point.x, point.z), p256FieldAdd(point.x, point.z)))
    let s = p256FieldDouble(p256FieldMultiply(point.y, point.z))
    let r = p256FieldMultiply(point.y, s)
    let beta = p256FieldDouble(p256FieldMultiply(point.x, r))
    let h    = p256FieldSubtract(p256FieldSquare(w), p256FieldDouble(beta))
    let y    = p256FieldSubtract(p256FieldMultiply(w, p256FieldSubtract(beta, h)), p256FieldDouble(p256FieldSquare(r)))

    // This doubling gives X = Z = 0 at infinity. Supply its nonzero Y.
    let infinity = p256FieldEqual(point.z, P256Field{})
    return {x: p256FieldMultiply(h, s),
            y: p256FieldSelect(y, P256Field{limbs: P256MontgomeryOne}, infinity),
            z: p256FieldMultiply(s, p256FieldSquare(s))}
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

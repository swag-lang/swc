#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Ed25519 private seeds and public keys are 32 bytes; signatures are 64 bytes.
public const Ed25519KeySize = 32

// Ed25519 signature size in bytes.
public const Ed25519SignatureSize = 64

private const Ed25519Order: [5] u64 = [
    0x5812_631A_5CF5_D3ED, 0x14DE_F9DE_A2F7_9CD6, 0, 0x1000_0000_0000_0000, 0]

// Floor(2^512 / Ed25519Order), in radix 2^64.
private const Ed25519Reciprocal: [5] u64 = [
    0xED9C_E5A3_0A2C_131B, 0x2106_215D_0863_29A7, 0xFFFF_FFFF_FFFF_FFEB,
    0xFFFF_FFFF_FFFF_FFFF, 0x0000_0000_0000_000F]

private struct Ed25519Point
{
    x: X25519Field
    y: X25519Field
    z: X25519Field
    t: X25519Field
}

private struct Ed25519Affine
{
    yMinusX, yPlusX, twiceDT: X25519Field
}

private struct Ed25519Cached
{
    affine: Ed25519Affine
    twiceZ: X25519Field
}

private func ed25519FieldConstant(limbs: [5] u64)->X25519Field
{
    var result: #returntype
    result.limbs = limbs
    return result
}

private func ed25519D()->X25519Field
{
    return ed25519FieldConstant([0x3_4DCA_1359_78A3, 0x1_A828_3B15_6EBD, 0x5_E7A2_6001_C029,
                                 0x7_39C6_63A0_3CBB, 0x5_2036_CEE2_B6FF])
}

private func ed25519SqrtMinusOne()->X25519Field
{
    return ed25519FieldConstant([0x6_1B27_4A0E_A0B0, 0x0_D5A5_FC8F_189D, 0x7_EF5E_9CBD_0C60,
                                 0x7_8595_A680_4C9E, 0x2_B832_4804_FC1D])
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
    let z  = x25519Multiply(left.z, right.z)
    let d  = x25519Add(z, z)
    return ed25519CompleteAddition(a, b, c2, d)
}

private func ed25519Cache(point: Ed25519Point)->Ed25519Cached
{
    var result: #returntype
    result.affine.yMinusX = x25519Subtract(point.y, point.x)
    result.affine.yPlusX = x25519Add(point.y, point.x)
    let dt = x25519Multiply(ed25519D(), point.t)
    result.affine.twiceDT = x25519Add(dt, dt)
    result.twiceZ = x25519Add(point.z, point.z)
    return result
}

#[Swag.Inline]
private func ed25519AddPrepared(left: Ed25519Point, right: Ed25519Affine, twiceZ: X25519Field)->Ed25519Point
{
    let a  = x25519Multiply(x25519Subtract(left.y, left.x), right.yMinusX)
    let b  = x25519Multiply(x25519Add(left.y, left.x), right.yPlusX)
    let c2 = x25519Multiply(left.t, right.twiceDT)
    return ed25519CompleteAddition(a, b, c2, twiceZ)
}

private func ed25519AddAffine(left: Ed25519Point, right: Ed25519Affine)->Ed25519Point
{
    return ed25519AddPrepared(left, right, x25519Add(left.z, left.z))
}

private func ed25519AddCached(left: Ed25519Point, right: Ed25519Cached)->Ed25519Point
{
    return ed25519AddPrepared(left, right.affine, x25519Multiply(left.z, right.twiceZ))
}

#[Swag.Inline]
private func ed25519CompleteAddition(a, b, c2, d: X25519Field)->Ed25519Point
{
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

private func(UpdateT: bool) ed25519Double(point: Ed25519Point)->Ed25519Point
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
    #static if UpdateT do
        result.t = x25519Multiply(e, h)
    result.z = x25519Multiply(f, g)
    return result
}

// A subsequent doubling consumes X, Y and Z. A point addition also needs T.
private func ed25519DoubleRepeated(point: Ed25519Point, count: u32)->Ed25519Point
{
    var result = point
    for count - 1 do
        result = ed25519Double'(false)(result)
    return ed25519Double'(true)(result)
}

private func ed25519BuildMultiples(point: Ed25519Point)->[16] Ed25519Cached
{
    var result: #returntype
    result[0] = ed25519Cache(ed25519Identity())
    result[1] = ed25519Cache(point)
    var multiple = point
    for index in 2 until result.count
    {
        multiple = ed25519AddCached(multiple, result[1])
        result[index] = ed25519Cache(multiple)
    }
    return result
}

private func ed25519SelectMultiple(multiples: const [..] Ed25519Cached, digit: u8)->Ed25519Cached
{
    var result: #returntype
    for index in 16
    {
        let mask = 0'u64 - cast(u64, index == digit)
        for limb in result.twiceZ.limbs.count
        {
            result.affine.yMinusX.limbs[limb] |= multiples[index].affine.yMinusX.limbs[limb] & mask
            result.affine.yPlusX.limbs[limb]  |= multiples[index].affine.yPlusX.limbs[limb] & mask
            result.affine.twiceDT.limbs[limb] |= multiples[index].affine.twiceDT.limbs[limb] & mask
            result.twiceZ.limbs[limb]         |= multiples[index].twiceZ.limbs[limb] & mask
        }
    }
    return result
}

private func ed25519ScalarMultiply(multiples: const [..] Ed25519Cached, scalar: const [..] u8)->Ed25519Point
{
    var result = ed25519Identity()
    var selected: Ed25519Cached
    defer Crypto.secureClear(Swag.makeSlice(&selected, 1))
    for window in 2 * Ed25519KeySize
    {
        result = ed25519DoubleRepeated(result, 4)
        let nibbleIndex = 2 * Ed25519KeySize - 1 - window
        let digit = (scalar[nibbleIndex / 2] >> (4 * (nibbleIndex & 1))) & 15
        selected = ed25519SelectMultiple(multiples, digit)
        result   = ed25519AddCached(result, selected)
    }

    return result
}

private func ed25519BasePoint()->Ed25519Point
{
    var result: #returntype
    result.x = ed25519FieldConstant([0x6_2D60_8F25_D51A, 0x4_12A4_B4F6_592A, 0x7_5B71_71A4_B31D,
                                     0x1_FF60_5271_18FE, 0x2_1693_6D3C_D6E5])
    result.y = ed25519FieldConstant([0x6_6666_6666_6658, 0x4_CCCC_CCCC_CCCC, 0x1_9999_9999_9999,
                                     0x3_3333_3333_3333, 0x6_6666_6666_6666])
    result.z.limbs[0] = 1
    result.t = x25519Multiply(result.x, result.y)
    return result
}

// Row i stores the first eight multiples of 256^i times the base point.
private const Ed25519GeneratorRadix16 = #run ed25519BuildGeneratorRadix16()

private func ed25519BuildGeneratorRadix16()->[256] Ed25519Affine
{
    var points: [256] Ed25519Point
    var base = ed25519BasePoint()
    for row in 32
    {
        let start = row * 8
        points[start] = base
        for column in 1 until 8 do
            points[start + column] = ed25519Add(points[start + column - 1], base)
        if row < 31 do
            base = ed25519DoubleRepeated(base, 8)
    }

    // Normalize the public points with one inversion.
    var prefixes: [256] X25519Field
    var product: X25519Field
    product.limbs[0] = 1
    for point, index in points
    {
        prefixes[index] = product
        product = x25519Multiply(product, point.z)
    }

    var inverse = x25519InvertPublic(product)
    let twiceD = x25519Add(ed25519D(), ed25519D())
    var result: #returntype
    for row in points.count
    {
        let index = points.count - 1 - row
        let inverseZ = x25519Multiply(inverse, prefixes[index])
        inverse = x25519Multiply(inverse, points[index].z)
        let x = x25519Multiply(points[index].x, inverseZ)
        let y = x25519Multiply(points[index].y, inverseZ)
        result[index] = {yMinusX: x25519Subtract(y, x), yPlusX: x25519Add(y, x),
                         twiceDT: x25519Multiply(twiceD, x25519Multiply(x, y))}
    }

    return result
}

private func ed25519SelectAffine(multiples: const [..] Ed25519Affine, digit: s8)->Ed25519Affine
{
    let sign = digit >> 7
    let magnitude = cast(u8, ((digit ^ sign) - sign))
    var result: #returntype
    result.yMinusX.limbs[0] = cast(u64, magnitude == 0)
    result.yPlusX.limbs[0] = result.yMinusX.limbs[0]
    for entry, index in multiples
    {
        let mask = 0'u64 - cast(u64, index + 1 == magnitude)
        for limb in result.yMinusX.limbs.count
        {
            result.yMinusX.limbs[limb] |= entry.yMinusX.limbs[limb] & mask
            result.yPlusX.limbs[limb]  |= entry.yPlusX.limbs[limb] & mask
            result.twiceDT.limbs[limb] |= entry.twiceDT.limbs[limb] & mask
        }
    }

    // Negating an Edwards point swaps Y-X and Y+X, and negates 2dXY.
    let negativeMask = 0'u64 - cast(u64, sign != 0)
    var zero: X25519Field
    let negatedT = x25519Subtract(zero, result.twiceDT)
    for limb in result.yMinusX.limbs.count
    {
        let swap = (result.yMinusX.limbs[limb] ^ result.yPlusX.limbs[limb]) & negativeMask
        result.yMinusX.limbs[limb] ^= swap
        result.yPlusX.limbs[limb] ^= swap
        result.twiceDT.limbs[limb] ^= (result.twiceDT.limbs[limb] ^ negatedT.limbs[limb]) & negativeMask
    }

    return result
}

private func ed25519MultiplyGenerator(scalar: const [..] u8)->Ed25519Point
{
    // The caller supplies a clamped or reduced scalar below 2^255. Carrying
    // across its radix-16 digits gives signed digits in [-8, 8].
    var digits: [64] s8
    defer Crypto.secureClear(digits)
    for byte, index in scalar
    {
        digits[index * 2] = cast(s8, byte & 15)
        digits[index * 2 + 1] = cast(s8, byte >> 4)
    }

    var carry = 0's8
    for index in 63
    {
        let digit = digits[index] + carry
        carry = (digit + 8) >> 4
        digits[index] = digit - (carry << 4)
    }
    digits[63] += carry

    // Odd-position digits share the same rows as even digits after four doublings.
    var result = ed25519Identity()
    var selected: Ed25519Affine
    defer Crypto.secureClear(Swag.makeSlice(&selected, 1))
    for pass in 2
    {
        for row in 32
        {
            let table = Ed25519GeneratorRadix16[row * 8 until row * 8 + 8]
            selected = ed25519SelectAffine(table, digits[row * 2 + 1 - pass])
            result = ed25519AddAffine(result, selected)
        }
        if pass == 0 do
            result = ed25519DoubleRepeated(result, 4)
    }

    return result
}

// Edwards y = 4/5 maps to the X25519 generator u = 9. In projective
// coordinates the Montgomery map is u = (Z + Y) / (Z - Y).
internal func x25519MultiplyGenerator(scalar: const [..] u8, destination: [..] u8)
{
    var point = ed25519MultiplyGenerator(scalar)
    defer Crypto.secureClear(Swag.makeSlice(&point, 1))
    var numerator = x25519Add(point.z, point.y)
    defer Crypto.secureClear(numerator.limbs)
    var denominator = x25519Subtract(point.z, point.y)
    defer Crypto.secureClear(denominator.limbs)
    var coordinate = x25519Multiply(numerator, x25519Invert(denominator))
    defer Crypto.secureClear(coordinate.limbs)
    x25519Encode(coordinate, destination)
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

    // For u = y^2 - 1 and v = d*y^2 + 1, this recovers sqrt(u/v) as
    // u*v^3 * (u*v^7)^((p-5)/8). Checking x^2*v avoids an inversion.
    let v2  = x25519Square(denominator)
    let v3  = x25519Multiply(v2, denominator)
    let v7  = x25519Multiply(x25519Square(v3), denominator)
    let uv3 = x25519Multiply(numerator, v3)
    let uv7 = x25519Multiply(numerator, v7)
    var x   = x25519Multiply(uv3, x25519Pow252Minus3(uv7))

    let check = x25519Multiply(x25519Square(x), denominator)
    if not ed25519FieldEqual(check, numerator)
    {
        var zero: X25519Field
        if not ed25519FieldEqual(check, x25519Subtract(zero, numerator)) do
            return (ed25519Identity(), false)
        x = x25519Multiply(x, ed25519SqrtMinusOne())
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

// Multiplies little-endian words into a zeroed result of the requested width.
private func ed25519MultiplyWords(left, right: const [..] u64, result: [..] u64)
{
    for row in Math.min(left.count, result.count)
    {
        let word  = left[row]
        let count = Math.min(right.count, result.count - row)
        var carry = 0'u64
        for column in count
        {
            let product = Math.mulU64(word, right[column])
            let partial = result[row + column] + product.lo
            let sum     = partial + carry
            carry = product.hi + cast(u64, partial < product.lo) + cast(u64, sum < partial)
            result[row + column] = sum
        }

        if row + count < result.count do
            result[row + count] = carry
    }
}

private func ed25519SubtractWords(left, right: [5] u64, result: *[5] u64)->u64
{
    var borrow = 0'u64
    for index in 5
    {
        let difference = left[index] - right[index]
        result[][index] = difference - borrow
        borrow = cast(u64, left[index] < right[index]) | cast(u64, difference < borrow)
    }

    return borrow
}

private func ed25519Reduce(digest: const [..] u8)->[32] u8
{
    var scratch: struct
    {
        input: [8] u64
        reciprocalProduct: [10] u64
        product, remainder, difference: [5] u64
    }
    defer Crypto.secureClear(Swag.makeSlice(&scratch, 1))

    let words = cast(const [*] u64, digest.buffer)
    for index in 8 do
        scratch.input[index] = Math.littleEndianToNative(words[index])

    // Barrett's quotient estimate uses the high five input words and the
    // reciprocal. The resulting remainder is in [0, 3*Ed25519Order).
    ed25519MultiplyWords(scratch.input[3 until 8], Ed25519Reciprocal, scratch.reciprocalProduct)
    ed25519MultiplyWords(scratch.reciprocalProduct[5 until 10], Ed25519Order[until 4], scratch.product)
    discard ed25519SubtractWords(cast(*[5] u64, scratch.input.buffer)[], scratch.product, &scratch.remainder)

    for 2
    {
        let borrow = ed25519SubtractWords(scratch.remainder, Ed25519Order, &scratch.difference)
        let keep = 0'u64 - borrow
        for index in 5 do
            scratch.remainder[index] = (scratch.remainder[index] & keep) | (scratch.difference[index] & ~keep)
    }

    var result: #returntype
    let destination = cast([*] u64, result.buffer)
    for index in 4 do
        destination[index] = Math.nativeToLittleEndian(scratch.remainder[index])
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
    var words, difference: [5] u64
    let source = cast(const [*] u64, value.buffer)
    for index in 4 do
        words[index] = Math.littleEndianToNative(source[index])
    return ed25519SubtractWords(words, Ed25519Order, &difference) != 0
}

private func ed25519IsIdentity(point: Ed25519Point)->bool
{
    var zero: X25519Field
    return not ed25519FieldEqual(point.z, zero) and
           ed25519FieldEqual(point.x, zero) and
           ed25519FieldEqual(point.y, point.z)
}

private func ed25519IsPrimeSubgroup(point: Ed25519Point, multiples: const [..] Ed25519Cached)->bool
{
    // The public group order starts with digit one. Its remaining digits can
    // index the table directly, with only doublings for a zero digit.
    var result = point
    for window in 1 until 2 * Ed25519KeySize
    {
        for 3 do
            result = ed25519Double'(false)(result)
        let nibbleIndex = 2 * Ed25519KeySize - 1 - window
        let digit = (Ed25519Order[nibbleIndex / 16] >> (4 * (nibbleIndex & 15))) & 15
        if digit do
            result = ed25519AddCached(ed25519Double'(true)(result), multiples[digit])
        else do
            result = ed25519Double'(false)(result)
    }

    return ed25519IsIdentity(result)
}

private func ed25519PublicKeyFromExpanded(expanded: [64] u8)->[32] u8
{
    var scalar: [32] u8
    Swag.memcpy(&scalar[0], &expanded[0], 32)

    scalar[0]  &= 248
    scalar[31] &= 63
    scalar[31] |= 64
    var point   = ed25519MultiplyGenerator(scalar)
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
    var noncePoint  = ed25519MultiplyGenerator(nonce)
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
       ed25519IsIdentity(publicPoint) or
       ed25519IsIdentity(rPoint) do
        return false

    let multiples = ed25519BuildMultiples(publicPoint)
    if not ed25519IsPrimeSubgroup(publicPoint, multiples) do
        return false

    var challengeHash: Hash.Sha512
    challengeHash.reset()
    challengeHash.update(encodedR)
    challengeHash.update(publicKey)
    challengeHash.update(message)
    let challengeDigest = ed25519HashFinalize(&challengeHash)
    let challenge       = ed25519Reduce(challengeDigest)
    let left            = ed25519MultiplyGenerator(encodedS)
    let right           = ed25519Add(rPoint, ed25519ScalarMultiply(multiples, challenge))

    // The exact group equation forces R into the same subgroup as both scalar
    // multiples. Cross-products compare projective coordinates without inversions.
    let sameX    = ed25519FieldEqual(x25519Multiply(left.x, right.z), x25519Multiply(right.x, left.z))
    let sameY    = ed25519FieldEqual(x25519Multiply(left.y, right.z), x25519Multiply(right.y, left.z))
    let verified = (cast(u8, sameX) & cast(u8, sameY)) != 0
    Crypto.secureClear(challengeDigest)
    Crypto.secureClear(challenge)
    return verified
}

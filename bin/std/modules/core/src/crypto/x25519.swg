#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of an X25519 private or public key and shared secret.
public const X25519KeySize = 32

// Five radix-2^51 limbs represent any value below 2^255 before canonical reduction.
private const FieldLimbBits         = 51
private const FieldLimbMask         = (1'u64 << FieldLimbBits) - 1
private const FieldModulus: [5] u64 = [FieldLimbMask - 18, FieldLimbMask, FieldLimbMask, FieldLimbMask, FieldLimbMask]

// Arithmetic keeps every limb below 2^51, with limb 1 allowed another 255.
internal struct X25519Field
{
    limbs: [5] u64
}

private struct X25519Product
{
    low, high: u64
}

private impl X25519Product
{
    #[Swag.Inline]
    mtd add(value: u64)
    {
        let low = .low + value
        .high += cast(u64, low < .low)
        .low  = low
    }

    #[Swag.Inline]
    mtd addProduct(left, right: u64)
    {
        let product = Math.mulU64(left, right)
        .add(product.lo)
        .high += product.hi
    }

    // Even the wrapped sums stay below 2^109, so the carry fits in u64.
    #[Swag.Inline]
    mtd const carry() => (.low >> FieldLimbBits) | (.high << (64 - FieldLimbBits))
}

#[Swag.Inline]
private func x25519FoldCarry(value: *X25519Field, carry: u64)
{
    // The low limb can keep its full carry by advancing only to limb 1.
    // Even the product fold adds less than 128 radix-2^51 units there.
    value.limbs[0] += carry * 19
    value.limbs[1] += value.limbs[0] >> FieldLimbBits
    value.limbs[0] &= FieldLimbMask
}

private func x25519Normalize(value: X25519Field)->X25519Field
{
    var result = value
    for index in 4
    {
        let carry = result.limbs[index] >> FieldLimbBits
        result.limbs[index]     &= FieldLimbMask
        result.limbs[index + 1] += carry
    }

    let carry = result.limbs[4] >> FieldLimbBits
    result.limbs[4] &= FieldLimbMask
    x25519FoldCarry(&result, carry)
    return result
}

internal func x25519Add(left, right: X25519Field)->X25519Field
{
    var result: #returntype
    for index in result.limbs.count do
        result.limbs[index] = left.limbs[index] + right.limbs[index]
    return x25519Normalize(result)
}

internal func x25519Subtract(left, right: X25519Field)->X25519Field
{
    var result: #returntype
    for index in result.limbs.count do
        result.limbs[index] = left.limbs[index] + 2 * FieldModulus[index] - right.limbs[index]
    return x25519Normalize(result)
}

private func x25519ReduceProducts(products: *[5] X25519Product)->X25519Field
{
    var result: #returntype
    for index in 4
    {
        result.limbs[index] = products[][index].low & FieldLimbMask
        products[][index + 1].add(products[][index].carry())
    }

    result.limbs[4] = products[][4].low & FieldLimbMask
    x25519FoldCarry(&result, products[][4].carry())
    return result
}

internal func x25519Multiply(left, right: X25519Field)->X25519Field
{
    // A product past limb four wraps around with a factor of 19.
    let a       = left.limbs
    let b       = right.limbs
    let scaled1 = 19 * b[1]
    let scaled2 = 19 * b[2]
    let scaled3 = 19 * b[3]
    let scaled4 = 19 * b[4]
    var products: [5] X25519Product
    products[0].addProduct(a[0], b[0])
    products[0].addProduct(a[1], scaled4)
    products[0].addProduct(a[2], scaled3)
    products[0].addProduct(a[3], scaled2)
    products[0].addProduct(a[4], scaled1)

    products[1].addProduct(a[0], b[1])
    products[1].addProduct(a[1], b[0])
    products[1].addProduct(a[2], scaled4)
    products[1].addProduct(a[3], scaled3)
    products[1].addProduct(a[4], scaled2)

    products[2].addProduct(a[0], b[2])
    products[2].addProduct(a[1], b[1])
    products[2].addProduct(a[2], b[0])
    products[2].addProduct(a[3], scaled4)
    products[2].addProduct(a[4], scaled3)

    products[3].addProduct(a[0], b[3])
    products[3].addProduct(a[1], b[2])
    products[3].addProduct(a[2], b[1])
    products[3].addProduct(a[3], b[0])
    products[3].addProduct(a[4], scaled4)

    products[4].addProduct(a[0], b[4])
    products[4].addProduct(a[1], b[3])
    products[4].addProduct(a[2], b[2])
    products[4].addProduct(a[3], b[1])
    products[4].addProduct(a[4], b[0])
    return x25519ReduceProducts(&products)
}

internal func x25519Square(value: X25519Field)->X25519Field
{
    // Count each off-diagonal pair twice and apply the same modular wrap as multiplication.
    let a = value.limbs
    var products: [5] X25519Product
    products[0].addProduct(a[0], a[0])
    products[0].addProduct(a[1], 38 * a[4])
    products[0].addProduct(a[2], 38 * a[3])

    products[1].addProduct(a[0], 2 * a[1])
    products[1].addProduct(a[2], 38 * a[4])
    products[1].addProduct(a[3], 19 * a[3])

    products[2].addProduct(a[0], 2 * a[2])
    products[2].addProduct(a[1], a[1])
    products[2].addProduct(a[3], 38 * a[4])

    products[3].addProduct(a[0], 2 * a[3])
    products[3].addProduct(a[1], 2 * a[2])
    products[3].addProduct(a[4], 19 * a[4])

    products[4].addProduct(a[0], 2 * a[4])
    products[4].addProduct(a[1], 2 * a[3])
    products[4].addProduct(a[2], a[2])
    return x25519ReduceProducts(&products)
}

private func x25519SquareRepeated(value: X25519Field, count: u32)->X25519Field
{
    var result = value
    for count do
        result = x25519Square(result)
    return result
}

private func x25519Power(value: X25519Field, inverse: bool)->X25519Field
{
    // Build powers 2^n - 1 through 2^250 - 1. The suffix selects one of the
    // fixed exponents used for inversion and for recovering Edwards coordinates.
    var powers: struct
    {
        z2, z9, z11: X25519Field
        p5, p10, p20, p40, p50, p100, p200, p250: X25519Field
    }

    with powers
    {
        .z2   = x25519Square(value)
        .z9   = x25519Multiply(x25519SquareRepeated(.z2, 2), value)
        .z11  = x25519Multiply(.z9, .z2)
        .p5   = x25519Multiply(x25519Square(.z11), .z9)
        .p10  = x25519Multiply(x25519SquareRepeated(.p5, 5), .p5)
        .p20  = x25519Multiply(x25519SquareRepeated(.p10, 10), .p10)
        .p40  = x25519Multiply(x25519SquareRepeated(.p20, 20), .p20)
        .p50  = x25519Multiply(x25519SquareRepeated(.p40, 10), .p10)
        .p100 = x25519Multiply(x25519SquareRepeated(.p50, 50), .p50)
        .p200 = x25519Multiply(x25519SquareRepeated(.p100, 100), .p100)
        .p250 = x25519Multiply(x25519SquareRepeated(.p200, 50), .p50)
    }

    defer Crypto.secureClear(Swag.makeSlice(&powers, 1))
    if inverse do
        return x25519Multiply(x25519SquareRepeated(powers.p250, 5), powers.z11)
    return x25519Multiply(x25519SquareRepeated(powers.p250, 2), value)
}

internal func x25519Invert(value: X25519Field)->X25519Field => x25519Power(value, inverse: true)

internal func x25519Pow252Minus3(value: X25519Field)->X25519Field => x25519Power(value, inverse: false)

internal func x25519Decode(data: const [..] u8)->X25519Field
{
    #[Swag.Inline]
    func loadWord(bytes: const [*] u8)->u64 => Math.littleEndianToNative(cast(const [*] u64, bytes)[0])

    let bytes = data.buffer
    return {limbs: [
        loadWord(bytes) & FieldLimbMask,
        (loadWord(bytes + 6) >> 3) & FieldLimbMask,
        (loadWord(bytes + 12) >> 6) & FieldLimbMask,
        (loadWord(bytes + 19) >> 1) & FieldLimbMask,
        (loadWord(bytes + 24) >> 12) & FieldLimbMask]}
}

internal func x25519Encode(value: X25519Field, destination: [..] u8)
{
    // The extra 19 produces a carry out of bit 255 exactly when the
    // value is at least 2^255 - 19. Use that carry to subtract the modulus.
    var canonical = value.limbs
    var carry = (canonical[0] + 19) >> FieldLimbBits
    for index in 1 until canonical.count do
        carry = (canonical[index] + carry) >> FieldLimbBits

    canonical[0] += 19 * carry
    for index in 4
    {
        carry = canonical[index] >> FieldLimbBits
        canonical[index]     &= FieldLimbMask
        canonical[index + 1] += carry
    }
    canonical[4] &= FieldLimbMask

    let words = cast([*] u64, destination.buffer)
    words[0] = Math.nativeToLittleEndian(canonical[0] | (canonical[1] << 51))
    words[1] = Math.nativeToLittleEndian((canonical[1] >> 13) | (canonical[2] << 38))
    words[2] = Math.nativeToLittleEndian((canonical[2] >> 26) | (canonical[3] << 25))
    words[3] = Math.nativeToLittleEndian((canonical[3] >> 39) | (canonical[4] << 12))
}

private func x25519ConditionalSwap(left, right: *X25519Field, swap: u64)
{
    let mask = 0'u64 - swap
    for index in left.limbs.count
    {
        let difference = (left[].limbs[index] ^ right[].limbs[index]) & mask
        left[].limbs[index]  ^= difference
        right[].limbs[index] ^= difference
    }
}

private func x25519ClampScalar(privateKey: const [..] u8)->[X25519KeySize] u8
{
    var result: #returntype
    Swag.memcpy(result.buffer, privateKey.buffer, X25519KeySize)
    result[0] &= 248
    result[31] = (result[31] & 63) | 64
    return result
}

private func x25519ScalarMult(privateKey, publicCoordinate: const [..] u8)->[X25519KeySize] u8
{
    var scalar = x25519ClampScalar(privateKey)
    var coordinate: [X25519KeySize] u8
    Swag.memcpy(coordinate.buffer, publicCoordinate.buffer, X25519KeySize)
    coordinate[31] &= 127

    var x1 = x25519Decode(coordinate)
    var x2: X25519Field
    x2.limbs[0] = 1
    var z2: X25519Field
    var x3 = x1
    var z3: X25519Field
    z3.limbs[0] = 1
    var swap     = 0'u64
    var position = 255'u32
    while position
    {
        position -= 1
        let bit = cast(u64, (scalar[position / 8] >> (position & 7)) & 1)
        swap ^= bit
        x25519ConditionalSwap(&x2, &x3, swap)
        x25519ConditionalSwap(&z2, &z3, swap)
        swap = bit

        let a  = x25519Add(x2, z2)
        let aa = x25519Square(a)
        let b  = x25519Subtract(x2, z2)
        let bb = x25519Square(b)
        let e  = x25519Subtract(aa, bb)
        let c  = x25519Add(x3, z3)
        let d  = x25519Subtract(x3, z3)
        let da = x25519Multiply(d, a)
        let cb = x25519Multiply(c, b)
        x3 = x25519Square(x25519Add(da, cb))
        z3 = x25519Multiply(x1, x25519Square(x25519Subtract(da, cb)))
        x2 = x25519Multiply(aa, bb)
        z2 = x25519Multiply(e, x25519Add(aa, x25519MultiplyBy121665(e)))
    }

    x25519ConditionalSwap(&x2, &x3, swap)
    x25519ConditionalSwap(&z2, &z3, swap)
    let resultField = x25519Multiply(x2, x25519Invert(z2))
    var result: #returntype
    x25519Encode(resultField, result)
    Crypto.secureClear(scalar)
    Crypto.secureClear(coordinate)
    Crypto.secureClear(x1.limbs)
    Crypto.secureClear(x2.limbs)
    Crypto.secureClear(z2.limbs)
    Crypto.secureClear(x3.limbs)
    Crypto.secureClear(z3.limbs)
    Crypto.secureClear(resultField.limbs)
    return result
}

private func x25519MultiplyBy121665(value: X25519Field)->X25519Field
{
    var products: [5] X25519Product
    for index in products.count do
        products[index].addProduct(value.limbs[index], 121665)
    return x25519ReduceProducts(&products)
}

// Computes an X25519 public key from a 32-byte private scalar.
//
// Both buffers must be exactly 32 bytes. The scalar is clamped as specified by RFC 7748.
// Fails with [[Core.Errors.BadParameterError]] when either length is invalid.
func x25519PublicKey(privateKey: const [..] u8, destination: [..] u8) fail
{
    if privateKey.count != X25519KeySize or destination.count != X25519KeySize do
        fail Errors.BadParameterError{"X25519 keys and outputs must be exactly 32 bytes"}

    var scalar = x25519ClampScalar(privateKey)
    defer Crypto.secureClear(scalar)
    x25519MultiplyGenerator(scalar, destination)
}

// Computes a 32-byte shared secret and rejects low-order peer keys that produce the all-zero result.
//
// All three buffers must be exactly 32 bytes. The peer coordinate's high bit is ignored as required
// by RFC 7748. Fails with [[Core.Errors.BadParameterError]] for invalid lengths or a low-order key.
func x25519SharedSecret(privateKey, peerPublicKey: const [..] u8, destination: [..] u8) fail
{
    if privateKey.count != X25519KeySize or
       peerPublicKey.count != X25519KeySize or
       destination.count != X25519KeySize do
        fail Errors.BadParameterError{"X25519 keys and outputs must be exactly 32 bytes"}

    let result  = x25519ScalarMult(privateKey, peerPublicKey)
    var nonzero = 0'u8
    for byte in result do
        nonzero |= byte
    if not nonzero
    {
        Crypto.secureClear(result)
        fail Errors.BadParameterError{"X25519 peer key has low order"}
    }

    Swag.memcpy(destination.buffer, &result[0], X25519KeySize)
    Crypto.secureClear(result)
}

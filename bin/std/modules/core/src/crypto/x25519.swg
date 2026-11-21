#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of an X25519 private or public key and shared secret.
public const X25519KeySize = 32

internal struct X25519Field
{
    limbs: [16] u64
}

internal func x25519Normalize(value: X25519Field)->X25519Field
{
    var result = value
    for pass in 5
    {
        discard pass
        for index in 15
        {
            let carry = result.limbs[index] >> 16
            result.limbs[index]     &= 0xFFFF
            result.limbs[index + 1] += carry
        }

        let carry = result.limbs[15] >> 15
        result.limbs[15] &= 0x7FFF
        result.limbs[0]  += carry * 19
    }

    return result
}

internal func x25519Add(left, right: X25519Field)->X25519Field
{
    var result: #returntype
    for index in 16 do
        result.limbs[index] = left.limbs[index] + right.limbs[index]
    return x25519Normalize(result)
}

internal func x25519Subtract(left, right: X25519Field)->X25519Field
{
    var result: #returntype
    for index in 16
    {
        let modulusLimb = index == 0 ? 65517'u64 : index == 15 ? 32767'u64 : 65535'u64
        result.limbs[index] = left.limbs[index] + 2 * modulusLimb - right.limbs[index]
    }

    return x25519Normalize(result)
}

internal func x25519Multiply(left, right: X25519Field)->X25519Field
{
    var products: [32] u64
    for i in 16
    {
        for j in 16 do
            products[i + j] += left.limbs[i] * right.limbs[j]
    }

    for index in 16 until 32 do
        products[index - 16] += products[index] * 38

    var result: #returntype
    for index in 16 do
        result.limbs[index] = products[index]
    return x25519Normalize(result)
}

internal func x25519Square(value: X25519Field)->X25519Field
{
    return x25519Multiply(value, value)
}

internal func x25519Invert(value: X25519Field)->X25519Field
{
    // p - 2 = 2^255 - 21; this fixed exponent has no secret-dependent control flow.
    var result: X25519Field
    result.limbs[0] = 1
    var bit = 255'u32
    while bit
    {
        bit    -= 1
        result = x25519Square(result)
        if bit >= 8 or ((0xEB'u32 >> bit) & 1) do
            result = x25519Multiply(result, value)
    }

    return result
}

internal func x25519Decode(data: const [..] u8)->X25519Field
{
    var result: #returntype
    for index in 16
    {
        let offset = index * 2
        result.limbs[index] = cast(u64, data[offset]) | (cast(u64, data[offset + 1]) << 8)
    }

    result.limbs[15] &= 0x7FFF
    return result
}

internal func x25519Encode(value: X25519Field, destination: [..] u8)
{
    var canonical         = x25519Normalize(value)
    let modulus: [16] u64 = [65517, 65535, 65535, 65535, 65535, 65535, 65535, 65535,
                             65535, 65535, 65535, 65535, 65535, 65535, 65535, 32767]
    for reduction in 2
    {
        discard reduction
        var difference: [16] u64
        var borrow = 0'u64
        for index in 16
        {
            let sub       = modulus[index] + borrow
            let underflow = canonical.limbs[index] < sub
            difference[index] = (canonical.limbs[index] - sub) & (index == 15 ? 0x7FFF'u64 : 0xFFFF'u64)
            borrow = cast(u64, underflow)
        }

        let selectDifference = 0'u64 - (1 - borrow)
        for index in 16 do
            canonical.limbs[index] = (difference[index] & selectDifference) |
                                     (canonical.limbs[index] & ~selectDifference)
    }

    for index in X25519KeySize
    {
        let limb = canonical.limbs[index / 2]
        destination[index] = cast(u8, (limb >> cast(u32, (index & 1) * 8)) & 0xFF)
    }
}

private func x25519ConditionalSwap(left, right: *X25519Field, swap: u64)
{
    let mask = 0'u64 - swap
    for index in 16
    {
        let difference = (left[].limbs[index] ^ right[].limbs[index]) & mask
        left[].limbs[index]  ^= difference
        right[].limbs[index] ^= difference
    }
}

private func x25519ScalarMult(privateKey, publicCoordinate: const [..] u8)->[X25519KeySize] u8
{
    var scalar:     [X25519KeySize] u8
    var coordinate: [X25519KeySize] u8
    Swag.memcpy(&scalar[0], privateKey.buffer, X25519KeySize)
    Swag.memcpy(&coordinate[0], publicCoordinate.buffer, X25519KeySize)
    scalar[0]      &= 248
    scalar[31]     &= 127
    scalar[31]     |= 64
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
        z2 = x25519Multiply(e, x25519Add(aa, x25519Multiply(x25519Field121665(), e)))
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

private func x25519Field121665()->X25519Field
{
    var result: #returntype
    result.limbs[0] = 121665
    return result
}

// Computes an X25519 public key from a 32-byte private scalar.
//
// Both buffers must be exactly 32 bytes. The scalar is clamped as specified by RFC 7748.
// Fails with [[Core.Errors.BadParameterError]] when either length is invalid.
func x25519PublicKey(privateKey: const [..] u8, destination: [..] u8) fail
{
    if privateKey.count != X25519KeySize or destination.count != X25519KeySize do
        fail Errors.BadParameterError{"X25519 keys and outputs must be exactly 32 bytes"}

    var baseCoordinate: [X25519KeySize] u8
    baseCoordinate[0] = 9
    let result = x25519ScalarMult(privateKey, baseCoordinate)
    Swag.memcpy(destination.buffer, &result[0], X25519KeySize)
    Crypto.secureClear(result)
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

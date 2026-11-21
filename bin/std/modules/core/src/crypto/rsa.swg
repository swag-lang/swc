#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Minimum RSA modulus size accepted by this API, in bytes (2048 bits).
public const RsaMinModulusSize = 256

// Maximum RSA modulus size accepted by this API, in bytes (4096 bits).
public const RsaMaxModulusSize = 512

// SHA-256 digest and RSA-OAEP/PSS salt size, in bytes.
public const RsaSha256Size = 32

private struct RsaMontgomery
{
    modulus:   [128] u32
    r2:        [128] u32
    limbCount: u32
    byteCount: u32
    n0Inverse: u32
}

private func rsaMontgomeryClear(context: *RsaMontgomery)
{
    Crypto.secureClear(context[].modulus)
    Crypto.secureClear(context[].r2)
    context[].limbCount = 0
    context[].byteCount = 0
    context[].n0Inverse = 0
}

private func rsaDoubleModulo(value: *[128] u32, context: *RsaMontgomery)
{
    var doubled: [128] u32
    var carry = 0'u64
    for index in context[].limbCount
    {
        let word = (cast(u64, value[][index]) << 1) | carry
        doubled[index] = cast(u32, word)
        carry = word >> 32
    }

    var difference: [128] u32
    var borrow = 0'u64
    for index in context[].limbCount
    {
        let subtrahend = cast(u64, context[].modulus[index]) + borrow
        let word       = cast(u64, doubled[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    let useDifference = cast(u32, (carry != 0) or (borrow == 0))
    let mask = 0'u32 - useDifference
    for index in context[].limbCount do
        value[][index] = (difference[index] & mask) | (doubled[index] & ~mask)
    Crypto.secureClear(doubled)
    Crypto.secureClear(difference)
}

private func rsaMontgomeryCreate(modulus: const [..] u8)->RsaMontgomery fail
{
    if modulus.count < RsaMinModulusSize or
       modulus.count > RsaMaxModulusSize or
       modulus.count % 4 or
       modulus[0] < 0x80 or
       not (modulus[modulus.count - 1] & 1) do
        fail Errors.BadParameterError{"RSA modulus must be an odd, full-width value between 2048 and 4096 bits"}

    var result: RsaMontgomery
    result.byteCount = cast(u32, modulus.count)
    result.limbCount = cast(u32, modulus.count / 4)
    for index in result.limbCount
    {
        let offset = modulus.count - (cast(u64, index + 1) * 4)
        result.modulus[index] = (cast(u32, modulus[offset]) << 24) |
                                (cast(u32, modulus[offset + 1]) << 16) |
                                (cast(u32, modulus[offset + 2]) << 8) |
                                cast(u32, modulus[offset + 3])
    }

    var inverse = 1'u32
    for 5 do
        inverse *= 2 - result.modulus[0] * inverse
    result.n0Inverse = 0'u32 - inverse

    var r2: [128] u32
    r2[0] = 1
    for result.limbCount * 64 do
        rsaDoubleModulo(&r2, &result)
    result.r2 = r2
    Crypto.secureClear(r2)
    return result
}

private func rsaDecodeNumber(bytes: const [..] u8, context: *RsaMontgomery)->[128] u32 fail
{
    if bytes.count != context[].byteCount do
        fail Errors.BadParameterError{"RSA integer must match the modulus width"}

    var result: #returntype
    for index in context[].limbCount
    {
        let offset = bytes.count - (cast(u64, index + 1) * 4)
        result[index] = (cast(u32, bytes[offset]) << 24) |
                        (cast(u32, bytes[offset + 1]) << 16) |
                        (cast(u32, bytes[offset + 2]) << 8) |
                        cast(u32, bytes[offset + 3])
    }

    var lessThanModulus = false
    var equalToModulus  = true
    var index = context[].limbCount
    while index
    {
        index -= 1
        if result[index] < context[].modulus[index]
        {
            lessThanModulus = true
            equalToModulus  = false
            break
        }

        if result[index] > context[].modulus[index]
        {
            equalToModulus = false
            break
        }
    }

    if not lessThanModulus and not equalToModulus do
        fail Errors.BadParameterError{"RSA integer must be smaller than the modulus"}
    return result
}

private func rsaMontgomeryMultiply(left, right: [128] u32, context: *RsaMontgomery)->[128] u32
{
    var temporary: [129] u32
    for index in context[].limbCount
    {
        var carry = 0'u64
        for word in context[].limbCount
        {
            let product = cast(u64, left[word]) * right[index] + temporary[word] + carry
            temporary[word] = cast(u32, product)
            carry = product >> 32
        }

        let productTop = cast(u64, temporary[context[].limbCount]) + carry
        temporary[context[].limbCount] = cast(u32, productTop)

        let reduction = temporary[0] * context[].n0Inverse
        carry = 0
        for word in context[].limbCount
        {
            let product = cast(u64, reduction) * context[].modulus[word] + temporary[word] + carry
            if word do
                temporary[word - 1] = cast(u32, product)
            carry = product >> 32
        }

        let top = cast(u64, temporary[context[].limbCount]) + carry
        temporary[context[].limbCount - 1] = cast(u32, top)
        temporary[context[].limbCount]     = cast(u32, top >> 32)
    }

    var difference: [128] u32
    var borrow = 0'u64
    for index in context[].limbCount
    {
        let subtrahend = cast(u64, context[].modulus[index]) + borrow
        let word       = cast(u64, temporary[index]) - subtrahend
        difference[index] = cast(u32, word)
        borrow = word >> 63
    }

    var result: #returntype
    let useDifference = cast(u32, (temporary[context[].limbCount] != 0) or (borrow == 0))
    let mask = 0'u32 - useDifference
    for index in context[].limbCount do
        result[index] = (difference[index] & mask) | (temporary[index] & ~mask)
    Crypto.secureClear(temporary)
    Crypto.secureClear(difference)
    return result
}

private func rsaExponentBit(exponent: const [..] u8, bit: u64)->u32
{
    let byte = exponent.count - 1 - (bit / 8)
    return (cast(u32, exponent[byte]) >> cast(u32, bit % 8)) & 1
}

private func rsaModularPower(base: [128] u32, exponent: const [..] u8, fixedTime: bool, context: *RsaMontgomery)->[128] u32 fail
{
    var one: [128] u32
    one[0] = 1
    let baseMontgomery = rsaMontgomeryMultiply(base, context[].r2, context)
    var result         = rsaMontgomeryMultiply(one, context[].r2, context)
    var bitCount       = exponent.count * 8
    if fixedTime do
        bitCount = context[].byteCount * 8
    for step in bitCount
    {
        let bit     = rsaExponentBit(exponent, bitCount - 1 - step)
        var squared = rsaMontgomeryMultiply(result, result, context)
        var product: [128] u32
        if fixedTime or bit do
            product = rsaMontgomeryMultiply(squared, baseMontgomery, context)

        if fixedTime
        {
            let mask = 0'u32 - bit
            for index in context[].limbCount do
                squared[index] = (product[index] & mask) | (squared[index] & ~mask)
        }
        elif bit
        {
            squared = product
        }

        Crypto.secureClear(result)
        result = squared
        Crypto.secureClear(squared)
        Crypto.secureClear(product)
    }

    let ordinary = rsaMontgomeryMultiply(result, one, context)
    Crypto.secureClear(one)
    Crypto.secureClear(result)
    Crypto.secureClear(baseMontgomery)
    return ordinary
}

private func rsaEncodeNumber(value: [128] u32, context: *RsaMontgomery)->[512] u8
{
    var result: #returntype
    for index in context[].limbCount
    {
        let offset = context[].byteCount - (cast(u64, index + 1) * 4)
        result[offset]     = Math.byteAt(value[index], 3)
        result[offset + 1] = Math.byteAt(value[index], 2)
        result[offset + 2] = Math.byteAt(value[index], 1)
        result[offset + 3] = Math.byteAt(value[index], 0)
    }

    return result
}

private func rsaApply(modulus, exponent, input: const [..] u8, privateOperation: bool)->[512] u8 fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if exponent.count == 0 or exponent.count > modulus.count do
        fail Errors.BadParameterError{"RSA exponent must be a nonempty value no wider than the modulus"}
    if privateOperation and exponent.count != modulus.count do
        fail Errors.BadParameterError{"RSA private exponent must match the modulus width"}
    if privateOperation
    {
        var nonzero = 0'u8
        var less    = 0'u8
        var greater = 0'u8
        for index in modulus.count
        {
            nonzero |= exponent[index]
            let undecided = 1'u8 ^ (less | greater)
            let smaller   = cast(u8, exponent[index] < modulus[index])
            let larger    = cast(u8, exponent[index] > modulus[index])
            less    |= undecided & smaller
            greater |= undecided & larger
        }

        if nonzero == 0 or less == 0 do
            fail Errors.BadParameterError{"RSA private exponent must be a nonzero value smaller than the modulus"}
    }

    if not privateOperation and
       ((exponent[exponent.count - 1] & 1) == 0 or
        (exponent.count == 1 and exponent[0] < 3)) do
        fail Errors.BadParameterError{"RSA public exponent must be an odd integer greater than one"}

    let decoded = try rsaDecodeNumber(input, &context)
    let powered = try rsaModularPower(decoded, exponent, privateOperation, &context)
    let result  = rsaEncodeNumber(powered, &context)
    Crypto.secureClear(decoded)
    Crypto.secureClear(powered)
    return result
}

private func rsaSha256(data: const [..] u8)->[32] u8
{
    let digest = Hash.Sha256.compute(data)
    var result: #returntype
    for index in 8
    {
        result[index * 4]     = Math.byteAt(digest[index], 3)
        result[index * 4 + 1] = Math.byteAt(digest[index], 2)
        result[index * 4 + 2] = Math.byteAt(digest[index], 1)
        result[index * 4 + 3] = Math.byteAt(digest[index], 0)
    }

    return result
}

private func rsaMgf1Sha256(seed: const [..] u8, destination: [..] u8)
{
    var counter = 0'u32
    var offset  = 0'u64
    while offset < destination.count
    {
        var hash: Hash.Sha256
        hash.update(seed)
        var encodedCounter: [4] u8
        encodedCounter[0] = Math.byteAt(counter, 3)
        encodedCounter[1] = Math.byteAt(counter, 2)
        encodedCounter[2] = Math.byteAt(counter, 1)
        encodedCounter[3] = Math.byteAt(counter, 0)
        hash.update(encodedCounter)
        let digest = rsaSha256Bytes(hash.finalize())
        let count  = Math.min(destination.count - offset, RsaSha256Size)
        Swag.memcpy(destination.buffer + offset, &digest[0], count)
        hash.reset()
        Crypto.secureClear(encodedCounter)
        Crypto.secureClear(digest)
        offset  += count
        counter += 1
    }
}

private func rsaSha256Bytes(digest: Hash.Sha256.Digest)->[32] u8
{
    var result: #returntype
    for index in 8
    {
        result[index * 4]     = Math.byteAt(digest[index], 3)
        result[index * 4 + 1] = Math.byteAt(digest[index], 2)
        result[index * 4 + 2] = Math.byteAt(digest[index], 1)
        result[index * 4 + 3] = Math.byteAt(digest[index], 0)
    }

    return result
}

private func rsaValidPublicExponent(exponent: const [..] u8)->bool
{
    if exponent.count == 0 do
        return false
    var nonzero       = false
    var higherNonzero = false
    for byte in exponent.count
    {
        nonzero = nonzero or exponent[byte] != 0
        if byte + 1 < exponent.count do
            higherNonzero = higherNonzero or exponent[byte] != 0
    }

    return nonzero and
           (exponent[exponent.count - 1] & 1) != 0 and
           (higherNonzero or exponent[exponent.count - 1] >= 3)
}

private func rsaLessThan(left, right: const [..] u8)->bool
{
    if left.count != right.count do
        return left.count < right.count
    for index in left.count
    {
        if left[index] < right[index] do
            return true
        if left[index] > right[index] do
            return false
    }

    return false
}

private func rsaValidatePublicKey(modulus, exponent: const [..] u8) fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if not rsaValidPublicExponent(exponent) or
       exponent.count > modulus.count or
       not rsaLessThan(exponent, modulus) do
        fail Errors.BadParameterError{"RSA public exponent must be an odd integer greater than one and smaller than the modulus"}
}

// Encrypts a message with RSAES-OAEP using SHA-256 and MGF1-SHA-256 (RFC 8017).
//
// `modulus` is an unsigned big-endian integer from 256 through 512 bytes; `publicExponent` is an
// unsigned big-endian integer such as 65537. Ciphertext must be exactly the modulus width. Labels
// are authenticated context, not encrypted metadata. The message limit is modulus width minus
// 66 bytes. Fails with [[Core.Errors.BadParameterError]] for invalid key or buffer sizes.
public func rsaOaepSha256Encrypt(modulus, publicExponent, plaintext, label: const [..] u8, ciphertext: [..] u8) fail
{
    try rsaValidatePublicKey(modulus, publicExponent)
    let width = modulus.count
    if ciphertext.count != width or
       width < 2 * RsaSha256Size + 2 or
       plaintext.count > width - 2 * RsaSha256Size - 2 do
        fail Errors.BadParameterError{"RSA-OAEP needs a modulus-width output and a message at most modulus-width minus 66 bytes"}

    var encoded: [512] u8
    defer Crypto.secureClear(encoded)
    let dataLength = width - RsaSha256Size - 1
    let labelHash  = rsaSha256(label)
    defer Crypto.secureClear(labelHash)
    Swag.memcpy(&encoded[33], &labelHash[0], RsaSha256Size)
    let delimiter = dataLength - plaintext.count - 1
    encoded[33 + delimiter] = 1
    if plaintext.count do
        Swag.memcpy(&encoded[34 + delimiter], plaintext.buffer, plaintext.count)

    var seed: [RsaSha256Size] u8
    defer Crypto.secureClear(seed)
    try Crypto.randomBytes(seed)
    var dataMask: [512] u8
    defer Crypto.secureClear(dataMask)
    rsaMgf1Sha256(seed, dataMask[0 until dataLength])
    for index in dataLength do
        encoded[33 + index] ^= dataMask[index]

    var seedMask: [RsaSha256Size] u8
    defer Crypto.secureClear(seedMask)
    rsaMgf1Sha256(encoded[33 until width], seedMask)
    for index in RsaSha256Size do
        encoded[1 + index] = seed[index] ^ seedMask[index]

    var result = try rsaApply(modulus, publicExponent, encoded[0 until width], false)
    defer Crypto.secureClear(result)
    Swag.memcpy(ciphertext.buffer, &result[0], width)
}

// Decrypts RSAES-OAEP with SHA-256 and MGF1-SHA-256 (RFC 8017).
//
// `modulus`, `privateExponent`, and `ciphertext` are unsigned big-endian integers exactly the
// modulus width. `plaintext` must hold up to modulus width minus 66 bytes; the return value gives
// the actual message length. A malformed ciphertext or OAEP encoding fails with one generic
// [[Core.Errors.BadParameterError]] and leaves the destination untouched.
public func rsaOaepSha256Decrypt(modulus, privateExponent, ciphertext, label: const [..] u8, plaintext: [..] u8)->u64 fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if ciphertext.count != context.byteCount or
       privateExponent.count != context.byteCount or
       plaintext.count < context.byteCount - (2 * RsaSha256Size + 2) do
        fail Errors.BadParameterError{"RSA-OAEP needs modulus-width key and ciphertext values and a maximum-size plaintext destination"}
    if not rsaLessThan(ciphertext, modulus) do
        fail Errors.BadParameterError{"RSA-OAEP decoding failed"}

    var encoded = try rsaApply(modulus, privateExponent, ciphertext, true)
    defer Crypto.secureClear(encoded)
    let width      = context.byteCount
    let dataLength = width - RsaSha256Size - 1
    var seed: [RsaSha256Size] u8
    defer Crypto.secureClear(seed)
    var seedMask: [RsaSha256Size] u8
    defer Crypto.secureClear(seedMask)
    var dataMask: [512] u8
    defer Crypto.secureClear(dataMask)
    var dataBlock: [512] u8
    defer Crypto.secureClear(dataBlock)
    rsaMgf1Sha256(encoded[33 until width], seedMask)
    for index in RsaSha256Size do
        seed[index] = encoded[1 + index] ^ seedMask[index]
    rsaMgf1Sha256(seed, dataMask[0 until dataLength])
    for index in dataLength do
        dataBlock[index] = encoded[33 + index] ^ dataMask[index]

    let labelHash = rsaSha256(label)
    defer Crypto.secureClear(labelHash)
    var invalid = cast(u8, encoded[0] != 0)
    invalid |= cast(u8, not Crypto.constantTimeEqual(dataBlock[0 until RsaSha256Size], labelHash))
    var lookingForDelimiter = 1'u8
    var messageOffset       = 0'u64
    for index in RsaSha256Size until dataLength
    {
        let byte   = dataBlock[index]
        let isZero = cast(u8, byte == 0)
        let isOne  = cast(u8, byte == 1)
        invalid |= lookingForDelimiter & (1 ^ (isZero | isOne))
        let foundDelimiter = lookingForDelimiter & isOne
        let mask = 0'u64 - foundDelimiter
        messageOffset       = (messageOffset & ~mask) | ((index + 1) & mask)
        lookingForDelimiter &= isZero
    }

    invalid |= lookingForDelimiter
    if invalid do
        fail Errors.BadParameterError{"RSA-OAEP decoding failed"}

    let messageLength = dataLength - messageOffset
    if messageLength do
        Swag.memcpy(plaintext.buffer, &dataBlock[messageOffset], messageLength)
    return messageLength
}

// Signs with RSASSA-PSS using SHA-256 and a random 32-byte salt (RFC 8017).
//
// Modulus and private exponent are unsigned big-endian values; the private exponent and signature
// are exactly the modulus width. The key must be 2048 through 4096 bits. A fresh cryptographic
// salt is generated for every call. Fails with [[Core.Errors.BadParameterError]] for invalid
// key or output sizes and [[Swag.SystemError]] if secure randomness fails.
public func rsaPssSha256Sign(modulus, privateExponent, message: const [..] u8, signature: [..] u8) fail
{
    var context = try rsaMontgomeryCreate(modulus)
    defer rsaMontgomeryClear(&context)
    if privateExponent.count != context.byteCount or signature.count != context.byteCount do
        fail Errors.BadParameterError{"RSA-PSS needs modulus-width private exponent and signature values"}

    let width         = context.byteCount
    let dataLength    = width - RsaSha256Size - 1
    let paddingLength = width - (2 * RsaSha256Size) - 2
    let messageHash   = rsaSha256(message)
    defer Crypto.secureClear(messageHash)
    var salt: [RsaSha256Size] u8
    defer Crypto.secureClear(salt)
    try Crypto.randomBytes(salt)

    var hashInput: [8 + 2 * RsaSha256Size] u8
    defer Crypto.secureClear(hashInput)
    Swag.memcpy(&hashInput[8], &messageHash[0], RsaSha256Size)
    Swag.memcpy(&hashInput[8 + RsaSha256Size], &salt[0], RsaSha256Size)
    let encodedHash = rsaSha256(hashInput)
    defer Crypto.secureClear(encodedHash)

    var dataBlock: [512] u8
    defer Crypto.secureClear(dataBlock)
    dataBlock[paddingLength] = 1
    Swag.memcpy(&dataBlock[paddingLength + 1], &salt[0], RsaSha256Size)
    var mask: [512] u8
    defer Crypto.secureClear(mask)
    rsaMgf1Sha256(encodedHash, mask[0 until dataLength])
    var encoded: [512] u8
    defer Crypto.secureClear(encoded)
    for index in dataLength do
        encoded[index] = dataBlock[index] ^ mask[index]
    encoded[0] &= 0x7F
    Swag.memcpy(&encoded[dataLength], &encodedHash[0], RsaSha256Size)
    encoded[width - 1] = 0xBC

    var result = try rsaApply(modulus, privateExponent, encoded[0 until width], true)
    defer Crypto.secureClear(result)
    Swag.memcpy(signature.buffer, &result[0], width)
}

// Verifies an RSASSA-PSS SHA-256 signature with a 32-byte salt (RFC 8017).
//
// Returns false for an invalid signature. Modulus and public exponent are unsigned big-endian
// values, and signature is exactly the modulus width. Invalid key material or widths fail with
// [[Core.Errors.BadParameterError]].
public func rsaPssSha256Verify(modulus, publicExponent, message, signature: const [..] u8)->bool fail
{
    try rsaValidatePublicKey(modulus, publicExponent)
    if signature.count != modulus.count or not rsaLessThan(signature, modulus) do
        return false

    var encoded = try rsaApply(modulus, publicExponent, signature, false)
    defer Crypto.secureClear(encoded)
    let width         = modulus.count
    let dataLength    = width - RsaSha256Size - 1
    let paddingLength = width - (2 * RsaSha256Size) - 2
    var invalid       = cast(u8, encoded[width - 1] != 0xBC or (encoded[0] & 0x80) != 0)
    var mask: [512] u8
    rsaMgf1Sha256(encoded[dataLength until dataLength + RsaSha256Size], mask[0 until dataLength])
    var dataBlock: [512] u8
    for index in dataLength do
        dataBlock[index] = encoded[index] ^ mask[index]
    dataBlock[0] &= 0x7F
    for index in paddingLength do
        invalid |= cast(u8, dataBlock[index] != 0)
    invalid |= cast(u8, dataBlock[paddingLength] != 1)

    let messageHash = rsaSha256(message)
    var hashInput: [8 + 2 * RsaSha256Size] u8
    Swag.memcpy(&hashInput[8], &messageHash[0], RsaSha256Size)
    Swag.memcpy(&hashInput[8 + RsaSha256Size], &dataBlock[paddingLength + 1], RsaSha256Size)
    let expectedHash = rsaSha256(hashInput)
    let valid        = invalid == 0 and Crypto.constantTimeEqual(expectedHash, encoded[dataLength until dataLength + RsaSha256Size])
    Crypto.secureClear(mask)
    Crypto.secureClear(dataBlock)
    Crypto.secureClear(messageHash)
    Crypto.secureClear(hashInput)
    Crypto.secureClear(expectedHash)
    return valid
}

#global public
#global namespace Crypto

// Minimum KMAC128 key size in bytes.
public const Kmac128KeyMinSize = 16

// Minimum KMAC256 key size in bytes.
public const Kmac256KeyMinSize = 32

private func kmacEncodeLeft(value: u64, destination: [*] u8)->u64
{
    var byteCount = 1_u64
    var remaining = value
    while remaining > 0xFF
    {
        byteCount += 1
        remaining >>= 8
    }

    destination[0] = cast(u8, byteCount)
    for index in byteCount
    {
        let shift = cast(u32, (byteCount - 1 - index) * 8)
        destination[1 + index] = cast(u8, (value >> shift) & 0xFF)
    }

    return byteCount + 1
}

private func kmacEncodeRight(value: u64, destination: *[9] u8)->u64
{
    var byteCount = 1_u64
    var remaining = value
    while remaining > 0xFF
    {
        byteCount += 1
        remaining >>= 8
    }

    for index in byteCount
    {
        let shift = cast(u32, (byteCount - 1 - index) * 8)
        destination[][index] = cast(u8, (value >> shift) & 0xFF)
    }

    destination[][byteCount] = cast(u8, byteCount)
    return byteCount + 1
}

private func kmacBytepadString(state: *[25] u64, rate: u64, value: const [..] u8) fail
{
    if value.count > Swag.U64.Max / 8
    {
        fail Errors.BadParameterError{"KMAC string is too long to encode"}
    }

    var prefix: [11] u8
    prefix[0] = 1
    prefix[1] = cast(u8, rate)
    let length = 2 + kmacEncodeLeft(value.count * 8, prefix.buffer + 2)
    Hash.absorbKmacBytepad(state, rate, prefix[until length], value)
}

private func kmacBytepadPrefix(state: *[25] u64, rate: u64, customization: const [..] u8) fail
{
    if customization.count > Swag.U64.Max / 8
    {
        fail Errors.BadParameterError{"KMAC customization is too long to encode"}
    }

    var prefix: [17] u8
    prefix[0] = 1
    prefix[1] = cast(u8, rate)
    prefix[2] = 1
    prefix[3] = 32
    prefix[4] = 'K'
    prefix[5] = 'M'
    prefix[6] = 'A'
    prefix[7] = 'C'
    let length = 8 + kmacEncodeLeft(customization.count * 8, prefix.buffer + 8)
    Hash.absorbKmacBytepad(state, rate, prefix[until length], customization)
}

private func kmacCompute(securityBits: u64, key, message, customization: const [..] u8, output: [..] u8, xof: bool) fail
{
    let minimumKeySize = securityBits / 8
    if key.count < minimumKeySize or not output.count
    {
        fail Errors.BadParameterError{"KMAC key is shorter than its security strength or output is empty"}
    }

    if key.count > Swag.U64.Max / 8 or output.count > Swag.U64.Max / 8
    {
        fail Errors.BadParameterError{"KMAC input or output is too long to encode"}
    }

    let rate = securityBits == 128 ? 168_u64 : 136_u64
    var state: [25] u64
    defer Crypto.secureClear(state)
    if customization.count
    {
        try kmacBytepadPrefix(&state, rate, customization)
    }
    else
    {
        Hash.seedEmptyKmacKeccak(&state, rate)
    }

    try kmacBytepadString(&state, rate, key)

    var outputLengthEncoding: [9] u8
    let outputBits    = xof ? 0 : output.count * 8
    let encodedLength = kmacEncodeRight(outputBits, &outputLengthEncoding)
    Hash.finalizeKmacKeccak(&state, rate, message, outputLengthEncoding[until encodedLength], output)
    Crypto.secureClear(outputLengthEncoding)
}

// Computes KMAC128 as specified by NIST SP 800-185.
//
// `key` must contain at least 16 bytes. `output` selects the fixed tag length; `customization`
// separates applications that share a key.
func kmac128(key, message, customization: const [..] u8, output: [..] u8) fail
{
    try kmacCompute(128, key, message, customization, output, false)
}

// Computes KMAC256 as specified by NIST SP 800-185.
//
// `key` must contain at least 32 bytes. `output` selects the fixed tag length; `customization`
// separates applications that share a key.
func kmac256(key, message, customization: const [..] u8, output: [..] u8) fail
{
    try kmacCompute(256, key, message, customization, output, false)
}

// Computes KMACXOF128, whose output length does not affect the sponge input.
//
// The key must contain at least 16 bytes.
func kmacXof128(key, message, customization: const [..] u8, output: [..] u8) fail
{
    try kmacCompute(128, key, message, customization, output, true)
}

// Computes KMACXOF256, whose output length does not affect the sponge input.
//
// The key must contain at least 32 bytes.
func kmacXof256(key, message, customization: const [..] u8, output: [..] u8) fail
{
    try kmacCompute(256, key, message, customization, output, true)
}

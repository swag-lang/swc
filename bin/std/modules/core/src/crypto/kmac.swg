#global public
#global namespace Crypto

// Minimum KMAC128 key size in bytes.
public const Kmac128KeyMinSize = 16

// Minimum KMAC256 key size in bytes.
public const Kmac256KeyMinSize = 32

private func kmacEncodeLeft(value: u64, destination: *[9] u8)->u64
{
    var byteCount = 1'u64
    var remaining = value
    while remaining > 0xFF
    {
        byteCount += 1
        remaining >>= 8
    }

    destination[][0] = cast(u8, byteCount)
    for index in byteCount
    {
        let shift = cast(u32, (byteCount - 1 - index) * 8)
        destination[][1 + index] = cast(u8, (value >> shift) & 0xFF)
    }

    return byteCount + 1
}

private func kmacEncodeRight(value: u64, destination: *[9] u8)->u64
{
    var byteCount = 1'u64
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

private func kmacBytepadString(shake: *Hash.Shake, rate: u64, value: const [..] u8) fail
{
    if value.count > Swag.U64.Max / 8 do
        fail Errors.BadParameterError{"KMAC string is too long to encode"}
    var widthEncoding:  [9] u8
    var lengthEncoding: [9] u8
    let widthLength  = kmacEncodeLeft(rate, &widthEncoding)
    let lengthLength = kmacEncodeLeft(value.count * 8, &lengthEncoding)
    let totalLength  = widthLength + lengthLength + value.count
    shake[].update(Swag.makeSlice(&widthEncoding[0], widthLength))
    shake[].update(Swag.makeSlice(&lengthEncoding[0], lengthLength))
    shake[].update(value)
    let padding = (rate - (totalLength % rate)) % rate
    if padding
    {
        var zeros: [Hash.Sha3MaxRate] u8
        shake[].update(Swag.makeSlice(&zeros[0], padding))
    }

    Crypto.secureClear(widthEncoding)
    Crypto.secureClear(lengthEncoding)
}

private func kmacBytepadPrefix(shake: *Hash.Shake, rate: u64, customization: const [..] u8) fail
{
    if customization.count > Swag.U64.Max / 8 do
        fail Errors.BadParameterError{"KMAC customization is too long to encode"}
    var widthEncoding:      [9] u8
    var nameLengthEncoding: [9] u8
    var customizationLengthEncoding: [9] u8
    let widthLength         = kmacEncodeLeft(rate, &widthEncoding)
    let nameLength          = kmacEncodeLeft(32, &nameLengthEncoding)
    let customizationLength = kmacEncodeLeft(customization.count * 8, &customizationLengthEncoding)
    let totalLength         = widthLength + nameLength + 4 + customizationLength + customization.count
    shake[].update(Swag.makeSlice(&widthEncoding[0], widthLength))
    shake[].update(Swag.makeSlice(&nameLengthEncoding[0], nameLength))
    shake[].update("KMAC")
    shake[].update(Swag.makeSlice(&customizationLengthEncoding[0], customizationLength))
    shake[].update(customization)
    let padding = (rate - (totalLength % rate)) % rate
    if padding
    {
        var zeros: [Hash.Sha3MaxRate] u8
        shake[].update(Swag.makeSlice(&zeros[0], padding))
    }

    Crypto.secureClear(widthEncoding)
    Crypto.secureClear(nameLengthEncoding)
    Crypto.secureClear(customizationLengthEncoding)
}

private func kmacCompute(securityBits: u64, key, message, customization: const [..] u8, output: [..] u8, xof: bool) fail
{
    let minimumKeySize = securityBits / 8
    if key.count < minimumKeySize or not output.count do
        fail Errors.BadParameterError{"KMAC key is shorter than its security strength or output is empty"}
    if key.count > Swag.U64.Max / 8 or output.count > Swag.U64.Max / 8 do
        fail Errors.BadParameterError{"KMAC input or output is too long to encode"}

    let rate  = securityBits == 128 ? 168'u64 : 136'u64
    var shake = try Hash.Shake.createCShake(securityBits)
    try kmacBytepadPrefix(&shake, rate, customization)
    try kmacBytepadString(&shake, rate, key)
    shake.update(message)

    var outputLengthEncoding: [9] u8
    let outputBits    = xof ? 0 : output.count * 8
    let encodedLength = kmacEncodeRight(outputBits, &outputLengthEncoding)
    shake.update(Swag.makeSlice(&outputLengthEncoding[0], encodedLength))
    try shake.finalize(output)
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

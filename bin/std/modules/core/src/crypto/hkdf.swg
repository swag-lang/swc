#global public
#global namespace Crypto

// Maximum output size for HKDF-SHA-256, in bytes.
public const HkdfSha256MaxOutputSize = 255 * 32

// Maximum output size for HKDF-SHA-512, in bytes.
public const HkdfSha512MaxOutputSize = 255 * 64

// Derives key material with HKDF-SHA-256 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-256 blocks.
func hkdfSha256(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha256MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-256 output exceeds 255 digest blocks"}
    if not destination.count do
        return

    var infoCopy: Array'u8
    var infoInput = info
    if info.count and destination.count
    {
        let infoStart   = cast(u64, info.buffer)
        let outputStart = cast(u64, destination.buffer)
        if infoStart < outputStart + destination.count and outputStart < infoStart + info.count
        {
            infoCopy.add(info)
            infoInput = infoCopy.toSlice()
        }
    }

    defer secureClear(infoCopy.toSlice())

    var pseudoRandomKey = HmacSha256.compute(salt, inputKeyMaterial)
    defer secureClear(pseudoRandomKey)

    var previous: HmacSha256Digest
    var hasPrevious = false
    var offset      = 0'u64
    var blockIndex  = 1'u8
    while offset < destination.count
    {
        var hmac = HmacSha256.create(pseudoRandomKey)
        if hasPrevious do
            hmac.update(previous)
        hmac.update(infoInput)
        hmac.update(Swag.makeSlice(&blockIndex, 1))
        previous    = hmac.finalize()
        hasPrevious = true
        let count = Math.min(destination.count - offset, #sizeof(previous))
        Swag.memcpy(destination.buffer + offset, &previous[0], count)
        offset += count
        if offset < destination.count do
            blockIndex += 1
    }

    secureClear(previous)
}

// Derives key material with HKDF-SHA-512 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-512 blocks.
func hkdfSha512(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha512MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-512 output exceeds 255 digest blocks"}
    if not destination.count do
        return

    var infoCopy: Array'u8
    var infoInput = info
    if info.count and destination.count
    {
        let infoStart   = cast(u64, info.buffer)
        let outputStart = cast(u64, destination.buffer)
        if infoStart < outputStart + destination.count and outputStart < infoStart + info.count
        {
            infoCopy.add(info)
            infoInput = infoCopy.toSlice()
        }
    }

    defer secureClear(infoCopy.toSlice())

    var pseudoRandomKey = HmacSha512.compute(salt, inputKeyMaterial)
    defer secureClear(pseudoRandomKey)

    var previous: HmacSha512Digest
    var hasPrevious = false
    var offset      = 0'u64
    var blockIndex  = 1'u8
    while offset < destination.count
    {
        var hmac = HmacSha512.create(pseudoRandomKey)
        if hasPrevious do
            hmac.update(previous)
        hmac.update(infoInput)
        hmac.update(Swag.makeSlice(&blockIndex, 1))
        previous    = hmac.finalize()
        hasPrevious = true
        let count = Math.min(destination.count - offset, #sizeof(previous))
        Swag.memcpy(destination.buffer + offset, &previous[0], count)
        offset += count
        if offset < destination.count do
            blockIndex += 1
    }

    secureClear(previous)
}

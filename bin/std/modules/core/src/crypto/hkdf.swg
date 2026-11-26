#global public
#global namespace Crypto

// Maximum output size for HKDF-SHA-256, in bytes.
public const HkdfSha256MaxOutputSize = 255 * 32

// Maximum output size for HKDF-SHA-512, in bytes.
public const HkdfSha512MaxOutputSize = 255 * 64

// Maximum output size for HKDF-SHA-224, in bytes.
public const HkdfSha224MaxOutputSize = 255 * 28

// Maximum output size for HKDF-SHA-384, in bytes.
public const HkdfSha384MaxOutputSize = 255 * 48

private func(Hmac, Digest) deriveHkdf(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8)
{
    if not destination.count do
        return

    var pseudoRandomKey = Hmac.compute(salt, inputKeyMaterial)
    defer secureClear(pseudoRandomKey)

    if destination.count <= #sizeof(Digest)
    {
        const FirstBlock = [1'u8]
        var hmac = Hmac.create(pseudoRandomKey)
        hmac.update(info)
        hmac.update(FirstBlock)
        var digest = hmac.finalize()
        Swag.memcpy(destination.buffer, digest.buffer, destination.count)
        secureClear(digest)
        return
    }

    var infoCopy: Array'u8
    var infoInput = info
    if info.count
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
    // Expansion uses the same inner and outer pad state for every block.
    let keyed = Hmac.create(pseudoRandomKey)
    var hmac: Hmac
    var previous: Digest
    defer secureClear(previous)

    var offset     = 0'u64
    var blockIndex = 1'u8
    while offset < destination.count
    {
        restoreHmacPrefix(&hmac, &keyed)
        if offset do
            hmac.update(previous)
        hmac.update(infoInput)
        hmac.update(Swag.makeSlice(&blockIndex, 1))
        previous = hmac.finalize()
        let count = Math.min(destination.count - offset, #sizeof(Digest))
        Swag.memcpy(destination.buffer + offset, previous.buffer, count)
        offset += count
        if offset < destination.count do
            blockIndex += 1
    }
}

// Derives key material with HKDF-SHA-256 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-256 blocks.
func hkdfSha256(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha256MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-256 output exceeds 255 digest blocks"}
    deriveHkdf'(HmacSha256, HmacSha256Digest)(salt, inputKeyMaterial, info, destination)
}

// Derives key material with HKDF-SHA-512 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-512 blocks.
func hkdfSha512(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha512MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-512 output exceeds 255 digest blocks"}
    deriveHkdf'(HmacSha512, HmacSha512Digest)(salt, inputKeyMaterial, info, destination)
}

// Derives key material with HKDF-SHA-224 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-224 blocks.
func hkdfSha224(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha224MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-224 output exceeds 255 digest blocks"}
    deriveHkdf'(HmacSha224, HmacSha224Digest)(salt, inputKeyMaterial, info, destination)
}

// Derives key material with HKDF-SHA-384 as specified by RFC 5869.
//
// `destination` may be empty. Output may overlap `info`; the original info bytes are preserved.
// An empty salt uses the RFC 5869 zero-filled default. Fails when output exceeds 255 SHA-384 blocks.
func hkdfSha384(salt, inputKeyMaterial, info: const [..] u8, destination: [..] u8) fail
{
    if destination.count > HkdfSha384MaxOutputSize do
        fail Errors.BadParameterError{"HKDF-SHA-384 output exceeds 255 digest blocks"}
    deriveHkdf'(HmacSha384, HmacSha384Digest)(salt, inputKeyMaterial, info, destination)
}

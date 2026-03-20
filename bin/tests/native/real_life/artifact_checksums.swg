#global fileprivate

// Real-life example: verify artifact checksums before accepting an import.

struct ArtifactDigest
{
    byteCount:    u32
    crc32:        u32
    crc64:        u64
    matchesCrc32: bool
    matchesCrc64: bool
}

#[Swag.CanOverflow(true)]
func computeCrc32(bytes: const [..] u8)->u32
{
    var crc = 0xFFFF_FFFF'u32
    foreach ch in bytes
    {
        crc ^= cast(u32) ch
        for 8
        {
            if (crc & 1'u32) != 0'u32 do
                crc = (crc >> 1) ^ 0xEDB8_8320'u32
            else do
                crc >>= 1
        }
    }

    return crc ^ 0xFFFF_FFFF'u32
}

#[Swag.CanOverflow(true)]
func computeCrc64(bytes: const [..] u8)->u64
{
    const Polynomial = 0x42F0_E1EB_A9EA_3693'u64

    var crc: u64
    foreach ch in bytes
    {
        crc ^= cast(u64) ch << 56
        for 8
        {
            if (crc & 0x8000_0000_0000_0000'u64) != 0'u64 do
                crc = (crc << 1) ^ Polynomial
            else do
                crc <<= 1
        }
    }

    return crc
}

func buildDigest(payload: string, expectedCrc32: u32, expectedCrc64: u64)->ArtifactDigest
{
    let bytes = cast(const [..] u8) payload

    var result: ArtifactDigest
    result.byteCount = cast(u32) @countof(bytes)
    result.crc32 = computeCrc32(bytes)
    result.crc64 = computeCrc64(bytes)
    result.matchesCrc32 = result.crc32 == expectedCrc32
    result.matchesCrc64 = result.crc64 == expectedCrc64
    return result
}

#test
{
    const manifest = "name,size,mtime\ntexture.png,24576,1712661000\nshader.bin,4096,1712662000"
    let manifestBytes = cast(const [..] u8) manifest

    @assert(@countof(manifestBytes) == 71)
    @assert(computeCrc32("") == 0x0000_0000'u32)
    @assert(computeCrc64("") == 0x0000_0000_0000_0000'u64)
    @assert(computeCrc32("123456789") == 0xCBF4_3926'u32)
    @assert(computeCrc64("123456789") == 0x6C40_DF5F_0B49_7347'u64)

    let digest = buildDigest(manifest, 0x4BDB_F65B'u32, 0x5533_3ADA_1E22_8DD4'u64)

    @assert(digest.byteCount == 71)
    @assert(digest.crc32 == 0x4BDB_F65B'u32)
    @assert(digest.crc64 == 0x5533_3ADA_1E22_8DD4'u64)
    @assert(digest.matchesCrc32)
    @assert(digest.matchesCrc64)
}

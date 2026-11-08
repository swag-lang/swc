//! Format: H.264 Annex B access-unit packetization.
//! Supported: Three- and four-byte start codes, AVC decoder configuration from SPS/PPS, and length-prefixed samples.
//! Not supported: Changing parameter sets after an MP4 writer has been initialized, or splitting an access unit across calls.
//! Role: This file converts a codec's Annex B output into the AVC layout consumed by MP4.
//
#global namespace H264
#global export

using Core, Core.Errors

private struct AnnexNal
{
    offset: u64
    size:   u32
    kind:   u8
}

// Owns an H.264 access unit in MP4's four-byte-length-prefixed form.
//
// `decoderConfig` is an AVCDecoderConfigurationRecord when this access unit carries both SPS and
// PPS NAL units, and is empty otherwise. Pass a configuration from the first key access unit to
// [[Video.Mp4.FragmentedWriter.create]] before submitting `bytes`. A later configuration change
// requires a new MP4 writer. A configuration-only access unit has no coded picture.
struct AnnexBAccessUnit
{
    public bytes:         Array'u8     // Owned length-prefixed NAL units, including in-band parameter sets.
    public decoderConfig: Array'u8     // Owned `avcC` record, or empty when no parameter sets occur.
    public isKeyFrame:    bool         // At least one IDR picture NAL occurs in this access unit.
    public hasPicture:    bool         // At least one coded picture NAL occurs in this access unit.
}

impl AnnexBAccessUnit
{
    // Converts one complete Annex B access unit into MP4 packet bytes and optional `avcC`.
    //
    // The input is borrowed only for this call. Leading and trailing zero bytes around start codes
    // are removed. Empty NAL units, broken headers, incomplete SPS/PPS pairs and units too large
    // for MP4's 32-bit NAL lengths are rejected.
    func parse(bytes: const [..] u8)->AnnexBAccessUnit fail
    {
        if bytes.count < 4 or bytes.count > Swag.U32.Max - 8 do
            fail InvalidFormatError{"H.264 Annex B access unit size is invalid"}

        var marker = findStart(bytes, 0)
        if marker == Swag.U64.Max do
            fail InvalidFormatError{"H.264 Annex B access unit has no start code"}
        for index in marker where bytes[index] != 0 do
            fail InvalidFormatError{"H.264 Annex B access unit has data before its first start code"}

        var nals:   Array'AnnexNal
        var sequenceCount = 0'u32
        var pictureCount  = 0'u32
        var result: #returntype
        while marker != Swag.U64.Max
        {
            let start = marker + 3
            marker = findStart(bytes, start)
            var end = marker == Swag.U64.Max ? bytes.count : marker
            while end > start and bytes[end - 1] == 0 do
                end -= 1
            if end == start or bytes[start] & 0x80 != 0 do
                fail InvalidFormatError{"H.264 Annex B access unit has an empty NAL or invalid header"}

            let size = end - start
            if size > Swag.U32.Max - 12 or
               result.bytes.count > Swag.U32.Max - 12 - size do
                fail UnsupportedFormatError{"H.264 NAL unit exceeds the MP4 length range"}
            let kind = bytes[start] & 31
            if not kind or kind > 23 do
                fail InvalidFormatError{"H.264 Annex B access unit has an unsupported NAL type"}
            if kind == 7
            {
                sequenceCount += 1
            }
            elif kind == 8
            {
                pictureCount += 1
            }
            elif kind == 5
            {
                result.isKeyFrame = true
                result.hasPicture = true
            }
            elif kind == 1
            {
                result.hasPicture = true
            }

            nals.add({start, cast(u32, size), kind})

            result.bytes.add(cast(u8, size >> 24))
            result.bytes.add(cast(u8, (size >> 16) & 0xFF))
            result.bytes.add(cast(u8, (size >> 8) & 0xFF))
            result.bytes.add(cast(u8, size & 0xFF))
            result.bytes.add(bytes[start until end])
        }

        if sequenceCount or pictureCount do
            try buildConfig(&result.decoderConfig, bytes, nals.toSlice(), sequenceCount, pictureCount)
        return result
    }
}

private impl AnnexBAccessUnit
{
    func findStart(bytes: const [..] u8, from: u64)->u64
    {
        var offset = from
        while offset + 3 <= bytes.count
        {
            if bytes[offset] == 0 and bytes[offset + 1] == 0 and bytes[offset + 2] == 1 do
                return offset
            offset += 1
        }

        return Swag.U64.Max
    }

    func buildConfig(config: *Array'u8, bytes: const [..] u8, nals: const [..] AnnexNal, sequenceCount, pictureCount: u32) fail
    {
        if not sequenceCount or not pictureCount or sequenceCount > 31 or pictureCount > 255 do
            fail InvalidFormatError{"H.264 Annex B access unit has incomplete or too many parameter sets"}

        var firstSequence: AnnexNal
        for nal in nals where nal.kind == 7
        {
            firstSequence = nal
            break
        }

        if firstSequence.size < 4 do
            fail InvalidFormatError{"H.264 sequence parameter set is too short for AVC configuration"}

        config.add(1'u8)
        config.add(bytes[firstSequence.offset + 1])
        config.add(bytes[firstSequence.offset + 2])
        config.add(bytes[firstSequence.offset + 3])
        config.add(0xFF'u8)
        config.add(cast(u8, 0xE0 | sequenceCount))
        for nal in nals where nal.kind == 7
        {
            if nal.size > Swag.U16.Max do
                fail UnsupportedFormatError{"H.264 parameter set exceeds the AVC configuration length range"}
            config.add(cast(u8, nal.size >> 8))
            config.add(cast(u8, nal.size & 0xFF))
            config.add(bytes[nal.offset until nal.offset + nal.size])
        }

        config.add(cast(u8, pictureCount))
        for nal in nals where nal.kind == 8
        {
            if nal.size > Swag.U16.Max do
                fail UnsupportedFormatError{"H.264 parameter set exceeds the AVC configuration length range"}
            config.add(cast(u8, nal.size >> 8))
            config.add(cast(u8, nal.size & 0xFF))
            config.add(bytes[nal.offset until nal.offset + nal.size])
        }
    }
}

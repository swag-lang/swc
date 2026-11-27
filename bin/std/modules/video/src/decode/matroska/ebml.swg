//! Format: Matroska/EBML container decoder component.
//! Supported: Bounded metadata and media elements used by the Matroska picture, audio, and text-subtitle reader.
//! Not supported: Picture codecs other than H.264, laced or invisible picture blocks, dependent E-AC-3 substreams, encrypted tracks, and writing Matroska.
//! Role: This file owns bounded EBML element identifiers, vint values, and cursor traversal.
//
#global namespace Matroska

using Core, Core.Errors

const EbmlId                 = 0x1A45DFA3_u32
const DocTypeId              = 0x4282_u32
const SegmentId              = 0x18538067_u32
const SeekHeadId             = 0x114D9B74_u32
const SeekId                 = 0x4DBB_u32
const SeekTargetId           = 0x53AB_u32
const SeekPositionId         = 0x53AC_u32
const InfoId                 = 0x1549A966_u32
const TimestampScaleId       = 0x2AD7B1_u32
const DurationId             = 0x4489_u32
const TracksId               = 0x1654AE6B_u32
const TrackEntryId           = 0xAE_u32
const TrackNumberId          = 0xD7_u32
const TrackTypeId            = 0x83_u32
const FlagEnabledId          = 0xB9_u32
const FlagDefaultId          = 0x88_u32
const DefaultDurationId      = 0x23E383_u32
const NameId                 = 0x536E_u32
const LanguageId             = 0x22B59C_u32
const LanguageIetfId         = 0x22B59D_u32
const CodecIdId              = 0x86_u32
const CodecPrivateId         = 0x63A2_u32
const CodecDelayId           = 0x56AA_u32
const SeekPreRollId          = 0x56BB_u32
const ContentEncodingsId     = 0x6D80_u32
const ContentEncodingId      = 0x6240_u32
const ContentEncodingScopeId = 0x5032_u32
const ContentEncodingTypeId  = 0x5033_u32
const ContentCompressionId   = 0x5034_u32
const ContentCompAlgoId      = 0x4254_u32
const ContentCompSettingsId  = 0x4255_u32
const VideoId                = 0xE0_u32
const PixelWidthId           = 0xB0_u32
const PixelHeightId          = 0xBA_u32
const DisplayWidthId         = 0x54B0_u32
const DisplayHeightId        = 0x54BA_u32
const DisplayUnitId          = 0x54B2_u32
const AudioId                = 0xE1_u32
const SamplingFrequencyId    = 0xB5_u32
const OutputSamplingFreqId   = 0x78B5_u32
const ChannelsId             = 0x9F_u32
const BitDepthId             = 0x6264_u32
const CuesId                 = 0x1C53BB6B_u32
const AttachmentsId          = 0x1941A469_u32
const ChaptersId             = 0x1043A770_u32
const TagsId                 = 0x1254C367_u32
const CuePointId             = 0xBB_u32
const CueTimeId              = 0xB3_u32
const CueTrackPositionsId    = 0xB7_u32
const CueTrackId             = 0xF7_u32
const CueClusterPositionId   = 0xF1_u32
const ClusterId              = 0x1F43B675_u32
const ClusterTimestampId     = 0xE7_u32
const SimpleBlockId          = 0xA3_u32
const BlockGroupId           = 0xA0_u32
const BlockId                = 0xA1_u32
const ReferenceBlockId       = 0xFB_u32
const BlockDurationId        = 0x9B_u32
const DiscardPaddingId       = 0x75A2_u32

// One bounded EBML element in a mapped stream.
struct Element
{
    id:        u32
    data:      u64
    end:       u64
    isUnknown: bool
}

// One EBML variable-width integer with its encoded byte count.
struct Vint
{
    value: u64
    width: u32
}

// Reads EBML metadata directly from mapped bytes.
//
// Payload ranges are represented by offsets and are never copied. Skipping a media block only
// advances an integer, so indexing a large Matroska file faults in its metadata pages rather than
// reading the compressed pictures and sound packets between them.
struct Cursor
{
    bytes:    const [..] u8
    position: u64
}

impl Cursor
{
    func open(bytes: const [..] u8)->Cursor => Cursor{bytes, 0}

    mtd seek(position: u64) fail
    {
        if position > (.bytes).count
        {
            fail InvalidFormatError{"Matroska element offset exceeds the stream size"}
        }

        .position = position
    }

    mtd readByte(limit: u64)->u8 fail
    {
        if .position >= limit or .position >= (.bytes).count
        {
            fail InvalidFormatError{"Matroska element ends before its value"}
        }

        let result = .bytes[.position]
        .position += 1
        return result
    }

    private mtd vintWidth(first: u8, maximum: u32)->u32 fail
    {
        var marker = 0x80_u8
        for width in 1 to maximum
        {
            if first & marker
            {
                return width
            }

            marker >>= 1
        }

        fail InvalidFormatError{"Matroska variable-width integer has no marker bit"}
    }

    private mtd readVint(limit: u64, maximum: u32, keepMarker: bool)->Vint fail
    {
        let first  = try .readByte(limit)
        let width  = try .vintWidth(first, maximum)
        let marker = 0x80_u8 >> (width - 1)
        var value  = keepMarker ? cast(u64, first) : cast(u64, (first & (marker - 1)))
        for 1 until width
        {
            value = (value << 8) | (try .readByte(limit))
        }

        return Vint{value, width}
    }

    // Reads an element header and bounds it by its parent.
    // Whether the sibling walk has reached its bound or a zero byte that cannot begin an EBML ID.
    //
    // The first byte of an element identifier always carries a marker bit, so a zero there begins
    // nothing. A file whose tail never made it to disk, or one written into space reserved ahead of
    // time and left unfilled, ends in a run of zeros: that is where its elements stop, and reading
    // on is reading nothing.
    mtd const atEnd(limit: u64)->bool
    {
        let end = Math.min(limit, (.bytes).count)
        return .position >= end or not .bytes[.position]
    }

    // Reads an element header and bounds it by its parent.
    mtd readElement(limit: u64)->Element fail
    {
        if limit > (.bytes).count
        {
            fail InvalidFormatError{"Matroska parent element exceeds the stream size"}
        }

        let idVint = try .readVint(limit, 4, true)
        if idVint.value > Swag.U32.Max
        {
            fail InvalidFormatError{"Matroska element identifier exceeds four bytes"}
        }

        let sizeFirst = try .readByte(limit)
        let sizeWidth = try .vintWidth(sizeFirst, 8)
        let marker    = 0x80_u8 >> (sizeWidth - 1)
        var size      = cast(u64, (sizeFirst & (marker - 1)))
        var unknown   = size == cast(u64, marker) - 1
        for 1 until sizeWidth
        {
            let value = try .readByte(limit)
            size    = (size << 8) | value
            unknown = unknown and value == 0xFF
        }

        if unknown
        {
            return Element{cast(u32, idVint.value), .position, limit, true}
        }

        if size > limit - .position
        {
            fail InvalidFormatError{"Matroska element size exceeds its parent"}
        }

        return Element{cast(u32, idVint.value), .position, .position + size, false}
    }

    // Reads an unsigned EBML element value.
    mtd readUnsigned(element: Element)->u64 fail
    {
        let size = element.end - element.data
        if not size or size > 8
        {
            fail InvalidFormatError{"Matroska integer needs between one and eight bytes"}
        }

        try .seek(element.data)
        var result = 0_u64
        for size
        {
            result = (result << 8) | (try .readByte(element.end))
        }

        return result
    }

    // Reads a signed EBML element value, two's complement over the element's own width.
    mtd readSigned(element: Element)->s64 fail
    {
        let size = element.end - element.data
        if not size or size > 8
        {
            fail InvalidFormatError{"Matroska integer needs between one and eight bytes"}
        }

        try .seek(element.data)
        var result = 0_u64
        for size
        {
            result = (result << 8) | (try .readByte(element.end))
        }

        let shift = cast(u32, (64 - 8 * size))
        return cast #bit (s64, (result << shift)) >> shift
    }

    // Reads a four- or eight-byte big-endian IEEE floating-point value.
    mtd readFloat(element: Element)->f64 fail
    {
        let size = element.end - element.data
        try .seek(element.data)
        if size == 4
        {
            var bits = 0_u32
            for 4
            {
                bits = (bits << 8) | (try .readByte(element.end))
            }

            return cast(f64, cast #bit (f32, bits))
        }

        if size == 8
        {
            var bits = 0_u64
            for 8
            {
                bits = (bits << 8) | (try .readByte(element.end))
            }

            return cast #bit (f64, bits)
        }

        fail InvalidFormatError{"Matroska floating-point value needs four or eight bytes"}
    }

    // Copies a string element into owned storage, without trailing zero padding.
    //
    // A string element states its length, and a writer that reserved room for a longer value fills
    // what it did not use with zeros. Those zeros are padding, not content, and clause 7 of the
    // specification says to read the value as ending at the first of them.
    mtd readString(element: Element)->String fail
    {
        try .seek(element.end)
        var size = element.end - element.data
        while size and not .bytes[element.data + size - 1]
        {
            size -= 1
        }

        return String.from(Swag.makeString((.bytes).buffer + element.data, size))
    }

    // Copies a binary element into owned storage.
    mtd readBytes(element: Element)->Array!{u8} fail
    {
        var result: #returntype
        let size = element.end - element.data
        result.resize(size)
        if size
        {
            Memory.copy(result.storage(), (.bytes).buffer + element.data, size)
        }

        try .seek(element.end)
        return result
    }

    // Reads a marker-stripped EBML variable-width value from the current position.
    mtd readVintValue(limit: u64)->Vint fail => try .readVint(limit, 8, false)

    // Reads the signed delta used by EBML lacing.
    mtd readSignedVint(limit: u64)->s64 fail
    {
        let encoded = try .readVint(limit, 8, false)
        let bits    = encoded.width * 7
        let bias    = cast(s64, ((1_u64 << (bits - 1)) - 1))
        return cast(s64, encoded.value) - bias
    }
}

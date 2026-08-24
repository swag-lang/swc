#global namespace Matroska

using Core, Core.Errors

const EbmlId               = 0x1A45DFA3'u32
const DocTypeId            = 0x4282'u32
const SegmentId            = 0x18538067'u32
const SeekHeadId           = 0x114D9B74'u32
const SeekId               = 0x4DBB'u32
const SeekTargetId         = 0x53AB'u32
const SeekPositionId       = 0x53AC'u32
const InfoId               = 0x1549A966'u32
const TimestampScaleId     = 0x2AD7B1'u32
const DurationId           = 0x4489'u32
const TracksId             = 0x1654AE6B'u32
const TrackEntryId         = 0xAE'u32
const TrackNumberId        = 0xD7'u32
const TrackTypeId          = 0x83'u32
const FlagEnabledId        = 0xB9'u32
const FlagDefaultId        = 0x88'u32
const DefaultDurationId    = 0x23E383'u32
const NameId               = 0x536E'u32
const LanguageId           = 0x22B59C'u32
const CodecIdId            = 0x86'u32
const CodecPrivateId       = 0x63A2'u32
const CodecDelayId         = 0x56AA'u32
const SeekPreRollId        = 0x56BB'u32
const ContentEncodingsId   = 0x6D80'u32
const VideoId              = 0xE0'u32
const PixelWidthId         = 0xB0'u32
const PixelHeightId        = 0xBA'u32
const AudioId              = 0xE1'u32
const SamplingFrequencyId  = 0xB5'u32
const OutputSamplingFreqId = 0x78B5'u32
const ChannelsId           = 0x9F'u32
const BitDepthId           = 0x6264'u32
const CuesId               = 0x1C53BB6B'u32
const CuePointId           = 0xBB'u32
const CueTimeId            = 0xB3'u32
const CueTrackPositionsId  = 0xB7'u32
const CueTrackId           = 0xF7'u32
const CueClusterPositionId = 0xF1'u32
const ClusterId            = 0x1F43B675'u32
const ClusterTimestampId   = 0xE7'u32
const SimpleBlockId        = 0xA3'u32
const BlockGroupId         = 0xA0'u32
const BlockId              = 0xA1'u32
const ReferenceBlockId     = 0xFB'u32
const BlockDurationId      = 0x9B'u32

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
    func open(bytes: const [..] u8)->Cursor => {bytes, 0}

    mtd seek(position: u64) fail
    {
        if position > @countof(.bytes) do
            fail InvalidFormatError{"Matroska element offset exceeds the stream size"}
        .position = position
    }

    mtd readByte(limit: u64)->u8 fail
    {
        if .position >= limit or .position >= @countof(.bytes) do
            fail InvalidFormatError{"Matroska element ends before its value"}
        let result = .bytes[.position]
        .position += 1
        return result
    }

    private mtd vintWidth(first: u8, maximum: u32)->u32 fail
    {
        var marker = 0x80'u8
        for width in 1 to maximum
        {
            if first & marker do
                return width
            marker >>= 1
        }

        fail InvalidFormatError{"Matroska variable-width integer has no marker bit"}
    }

    private mtd readVint(limit: u64, maximum: u32, keepMarker: bool)->Vint fail
    {
        let first  = .readByte(limit)
        let width  = .vintWidth(first, maximum)
        let marker = 0x80'u8 >> (width - 1)
        var value  = keepMarker ? cast(u64) first : cast(u64) (first & (marker - 1))
        for 1 until width do
            value = (value << 8) | .readByte(limit)
        return {value, width}
    }

    // Reads an element header and bounds it by its parent.
    mtd readElement(limit: u64)->Element fail
    {
        if limit > @countof(.bytes) do
            fail InvalidFormatError{"Matroska parent element exceeds the stream size"}
        let idVint = .readVint(limit, 4, true)
        if idVint.value > Swag.U32.Max do
            fail InvalidFormatError{"Matroska element identifier exceeds four bytes"}

        let sizeFirst = .readByte(limit)
        let sizeWidth = .vintWidth(sizeFirst, 8)
        let marker    = 0x80'u8 >> (sizeWidth - 1)
        var size      = cast(u64) (sizeFirst & (marker - 1))
        var unknown   = size == cast(u64) marker - 1
        for 1 until sizeWidth
        {
            let value = .readByte(limit)
            size    = (size << 8) | value
            unknown = unknown and value == 0xFF
        }

        if unknown do
            return {cast(u32) idVint.value, .position, limit, true}
        if size > limit - .position do
            fail InvalidFormatError{"Matroska element size exceeds its parent"}
        return {cast(u32) idVint.value, .position, .position + size, false}
    }

    // Reads an unsigned EBML element value.
    mtd readUnsigned(element: Element)->u64 fail
    {
        let size = element.end - element.data
        if !size or size > 8 do
            fail InvalidFormatError{"Matroska integer needs between one and eight bytes"}
        .seek(element.data)
        var result = 0'u64
        for size do
            result = (result << 8) | .readByte(element.end)
        return result
    }

    // Reads a four- or eight-byte big-endian IEEE floating-point value.
    mtd readFloat(element: Element)->f64 fail
    {
        let size = element.end - element.data
        .seek(element.data)
        if size == 4
        {
            var bits = 0'u32
            for 4 do
                bits = (bits << 8) | .readByte(element.end)
            return cast(f64) cast #bit (f32) bits
        }

        if size == 8
        {
            var bits = 0'u64
            for 8 do
                bits = (bits << 8) | .readByte(element.end)
            return cast #bit (f64) bits
        }

        fail InvalidFormatError{"Matroska floating-point value needs four or eight bytes"}
    }

    // Copies a textual element into owned storage.
    mtd readString(element: Element)->String fail
    {
        .seek(element.end)
        return String.from(@mkstring(@dataof(.bytes) + element.data, element.end - element.data))
    }

    // Copies a binary element into owned storage.
    mtd readBytes(element: Element)->Array'u8 fail
    {
        var result: retval
        let size = element.end - element.data
        result.resize(size)
        if size do
            Memory.copy(result.buffer!, @dataof(.bytes) + element.data, size)
        .seek(element.end)
        return result
    }

    // Reads a marker-stripped EBML variable-width value from the current position.
    mtd readVintValue(limit: u64)->Vint fail => .readVint(limit, 8, false)

    // Reads the signed delta used by EBML lacing.
    mtd readSignedVint(limit: u64)->s64 fail
    {
        let encoded = .readVint(limit, 8, false)
        let bits    = encoded.width * 7
        let bias    = cast(s64) ((1'u64 << (bits - 1)) - 1)
        return cast(s64) encoded.value - bias
    }
}

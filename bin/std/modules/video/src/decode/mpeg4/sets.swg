//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns bit reading, start codes, and the video object layer and plane headers.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors

// Video object plane coding types, clause 6.3.5.
const VopIntra         = 0'u32
const VopPredicted     = 1'u32
const VopBidirectional = 2'u32
const VopSprite        = 3'u32

// Start codes this decoder acts on, clause 6.3.1.
const CodeVideoObjectSequence    = 0xB0'u32
const CodeVideoObjectSequenceEnd = 0xB1'u32
const CodeUserData               = 0xB2'u32
const CodeGroupOfVop             = 0xB3'u32
const CodeVisualObject           = 0xB5'u32
const CodeVop                    = 0xB6'u32

// Reads syntax elements most significant bit first.
//
// Part 2 has no emulation prevention: an encoder keeps start codes out of the payload itself, so
// the bit reader works straight over the bytes of the plane.
struct BitReader
{
    data:   #null const [*] u8
    bitEnd: u64
    bitPos: u64
}

impl BitReader
{
    func create(payload: const [..] u8)->BitReader => {@dataof(payload), @countof(payload) * 8, 0}

    // Reads `count` bits. Past the end every bit reads as zero, and `overran` says so.
    mtd read(count: u32)->u32
    {
        var result = 0'u32
        for index in count
        {
            result <<= 1
            if .bitPos < .bitEnd
            {
                let byte = .data![.bitPos >> 3]
                result |= cast(u32) (byte >> (7 - cast(u32) (.bitPos & 7))) & 1
            }

            .bitPos += 1
        }

        return result
    }

    mtd bit()->u32 => .read(1)

    // Reads and discards the marker bit the format inserts to keep start codes out of a header.
    mtd marker()
    {
        discard .read(1)
    }

    mtd const overran()->bool => .bitPos > .bitEnd

    // Walks one variable length code through its tree and returns the entry it reaches.
    mtd decode(tree: const [..] s16)->s32
    {
        var node = 0's32
        for 24'u32
        {
            let slot = cast(u64) (node * 2) + cast(u64) .read(1)
            if slot >= @countof(tree) do
                return -1

            let next = tree[slot]
            if !next do
                return -1
            if next < 0 do
                return cast(s32) (-next - 1)
            node = cast(s32) next
        }

        return -1
    }
}

// What the setup headers of one video object layer state.
struct Layer
{
    versionId:          u32  = 1
    shape:              u32
    width:              u32     // Visible luma samples.
    height:             u32
    mbWidth:            u32     // Macroblocks across the coded picture.
    mbHeight:           u32
    timeIncrementBits:  u32  = 1
    timeResolution:     u32  = 30
    quantType:          u32
    quantPrecision:     u32  = 5
    bitsPerPixel:       u32  = 8
    intraMatrix:        [64] u8
    interMatrix:        [64] u8
    interlaced:         bool
    obmcDisabled:       bool = true
    spriteEnable:       u32
    quarterSample:      bool
    lowDelay:           bool
    complexityDisabled: bool = true
    dataPartitioned:    bool
    resyncDisabled:     bool
    configured:         bool
}

impl Layer
{
    // Installs the quantiser weights a layer that states none inherits.
    mtd useDefaultMatrices()
    {
        for index in 64'u64
        {
            .intraMatrix[index] = DefaultIntraMatrix[index]
            .interMatrix[index] = DefaultInterMatrix[index]
        }
    }

    // Reads one custom quantiser matrix, clause 6.2.3.
    //
    // The weights arrive in scan order and stop at the first zero, after which the last weight
    // read fills the rest.
    private mtd readMatrix(reader: *BitReader, target: *[64] u8)
    {
        var last  = 0'u32
        var index = 0'u64
        while index < 64
        {
            let value = reader.read(8)
            if !value do
                break
            last  = value
            target[][cast(u64) ScanZigzag[index]] = cast(u8) value
            index += 1
        }

        // Everything the stream did not state repeats the last weight it did.
        while index < 64
        {
            target[][cast(u64) ScanZigzag[index]] = cast(u8) last
            index += 1
        }
    }

    // Reads a video object layer header, clause 6.2.3.
    mtd readVideoObjectLayer(reader: *BitReader) fail
    {
        discard reader.bit()       // random_accessible_vol
        discard reader.read(8)     // video_object_type_indication

        .versionId = 1
        if reader.bit() != 0
        {
            .versionId = reader.read(4)
            discard reader.read(3)     // video_object_layer_priority
        }

        if reader.read(4) == 15 do
            discard reader.read(16)     // pixel aspect ratio

        if reader.bit() != 0
        {
            discard reader.read(2)     // chroma_format
            .lowDelay = reader.bit() != 0
            if reader.bit() != 0
            {
                // The buffer parameters describe a decoder's own timing and change no sample.
                discard reader.read(15)
                reader.marker()
                discard reader.read(15)
                reader.marker()
                discard reader.read(15)
                reader.marker()
                discard reader.read(3)
                discard reader.read(11)
                reader.marker()
                discard reader.read(15)
                reader.marker()
            }
        }

        .shape = reader.read(2)
        if .shape != 0 do
            fail UnsupportedFormatError{"video decoder reads rectangular MPEG-4 Part 2 objects only"}

        reader.marker()
        .timeResolution = reader.read(16)
        reader.marker()
        if !.timeResolution do
            fail InvalidFormatError{"MPEG-4 layer states a zero time resolution"}

        // The plane header spends as many bits on its time as the resolution needs.
        .timeIncrementBits = 1
        while (1'u32 << .timeIncrementBits) < .timeResolution and .timeIncrementBits < 16 do
            .timeIncrementBits += 1

        if reader.bit() != 0 do
            discard reader.read(.timeIncrementBits)     // fixed_vop_time_increment

        reader.marker()
        .width = reader.read(13)
        reader.marker()
        .height = reader.read(13)
        reader.marker()
        if !.width or !.height do
            fail InvalidFormatError{"MPEG-4 layer states an empty picture"}
        if .width > 4096 or .height > 4096 do
            fail UnsupportedFormatError{"MPEG-4 picture exceeds the supported size"}

        .interlaced = reader.bit() != 0
        if .interlaced do
            fail UnsupportedFormatError{"video decoder does not read interlaced MPEG-4 Part 2"}

        .obmcDisabled = reader.bit() != 0
        if !.obmcDisabled do
            fail UnsupportedFormatError{"video decoder does not read overlapped block motion compensation"}

        .spriteEnable = .versionId == 1 ? reader.read(1) : reader.read(2)
        if .spriteEnable do
            fail UnsupportedFormatError{"video decoder does not read MPEG-4 sprites or global motion compensation"}

        if reader.bit() != 0
        {
            .quantPrecision = reader.read(4)
            .bitsPerPixel   = reader.read(4)
            fail UnsupportedFormatError{"video decoder reads eight-bit MPEG-4 Part 2 only"}
        }

        .quantType = reader.read(1)
        .useDefaultMatrices()
        if .quantType != 0
        {
            if reader.bit() != 0 do
                .readMatrix(reader, &.intraMatrix)
            if reader.bit() != 0 do
                .readMatrix(reader, &.interMatrix)
        }

        .quarterSample = .versionId != 1 and reader.bit() != 0
        if .quarterSample do
            fail UnsupportedFormatError{"video decoder does not read quarter-sample MPEG-4 Part 2"}

        .complexityDisabled = reader.bit() != 0
        if !.complexityDisabled do
            fail UnsupportedFormatError{"video decoder does not read MPEG-4 complexity estimation"}

        .resyncDisabled  = reader.bit() != 0
        .dataPartitioned = reader.bit() != 0
        if .dataPartitioned do
            fail UnsupportedFormatError{"video decoder does not read data-partitioned MPEG-4 Part 2"}

        .mbWidth    = (.width + 15) / 16
        .mbHeight   = (.height + 15) / 16
        .configured = true
        if reader.overran() do
            fail InvalidFormatError{"MPEG-4 video object layer header is truncated"}
    }
}

// What one video object plane header states.
struct PlaneHeader
{
    codingType:       u32
    coded:            bool
    rounding:         u32
    intraDcThreshold: u32
    quant:            u32
    fcodeForward:     u32 = 1
    fcodeBackward:    u32 = 1
    timeIncrement:    u32
    moduloTime:       u32
}

// Reads a video object plane header, clause 6.2.5.
func readPlaneHeader(layer: const *Layer, reader: *BitReader, header: *PlaneHeader) fail
{
    header[]          = PlaneHeader{}
    header.codingType = reader.read(2)

    // The time base advances by one for every set bit before the zero that closes it.
    var guard = 0'u32
    while reader.bit() != 0
    {
        header.moduloTime += 1
        guard             += 1
        if guard > 64 do
            fail InvalidFormatError{"MPEG-4 plane header states an unbounded time base"}
    }

    reader.marker()
    header.timeIncrement = reader.read(layer.timeIncrementBits)
    reader.marker()

    header.coded = reader.bit() != 0
    if !header.coded do
        return

    if header.codingType == VopPredicted do
        header.rounding = reader.bit()

    header.intraDcThreshold = reader.read(3)
    header.quant            = reader.read(layer.quantPrecision)
    if !header.quant do
        fail InvalidFormatError{"MPEG-4 plane states a zero quantiser"}

    if header.codingType != VopIntra
    {
        header.fcodeForward = reader.read(3)
        if !header.fcodeForward do
            fail InvalidFormatError{"MPEG-4 plane states a zero forward code"}
    }

    if header.codingType == VopBidirectional
    {
        header.fcodeBackward = reader.read(3)
        if !header.fcodeBackward do
            fail InvalidFormatError{"MPEG-4 plane states a zero backward code"}
    }

    if reader.overran() do
        fail InvalidFormatError{"MPEG-4 plane header is truncated"}
}

// Finds the next start code at or after `at`, and returns where its payload begins.
//
// Returns the size of `bytes` when none is left.
func nextStartCode(bytes: const [..] u8, at: u64)->u64
{
    var index = at
    while index + 3 < @countof(bytes)
    {
        if bytes[index] == 0 and bytes[index + 1] == 0 and bytes[index + 2] == 1 do
            return index
        index += 1
    }

    return @countof(bytes)
}

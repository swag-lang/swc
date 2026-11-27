//! Format: H.264/AVC Annex B elementary byte stream.
//! Supported: Progressive pictures, stable SPS and PPS, multiple slices, picture reordering, and IDR seeks.
//! Not supported: Parameter-set changes, picture order resets between IDRs, and container timestamps.
//! Role: This file indexes byte ranges and feeds the decoded-picture stream.
//
#global namespace H264
#global internal

using Core, Core.Errors, Pixel

private const MaxAnnexAccessUnit = 64 * 1024 * 1024_u64
private const MaxAnnexFrames     = 1_048_576_u64

// The decoder caps every slice-header reference list and marking-operation list.
private const MaxAnnexSliceHeader = 16 * 1024_u64

// Copies a stored Annex B access unit into the same packet representation as the containers.
func packAnnexAccessUnit(bytes: const [..] u8, packet: *Array!{u8}) fail
{
    var source = ByteSource.openMemory(bytes)
    var scanner: AnnexBScanner
    try scanner.open(&source)

    packet.clear()
    var unit: AnnexBNal
    while try scanner.next(&source, &unit)
    {
        let size = unit.size
        packet.add(cast(u8, size >> 24))
        packet.add(cast(u8, ((size >> 16) & 255)))
        packet.add(cast(u8, ((size >> 8) & 255)))
        packet.add(cast(u8, (size & 255)))
        packet.add(bytes[unit.payload until unit.payload + size])
    }
}

// Compares the fields that identify the primary coded picture, section 7.4.1.2.4.
private func samePicture(a, b: SliceHeader, aIsReference, bIsReference: bool)->bool
{
    return a.frameNum == b.frameNum and
           a.ppsId == b.ppsId and
           aIsReference == bIsReference and
           a.pocLsb == b.pocLsb and
           a.deltaPocBottom == b.deltaPocBottom and
           a.deltaPoc0 == b.deltaPoc0 and
           a.deltaPoc1 == b.deltaPoc1 and
           a.isIdr == b.isIdr and
           a.idrPicId == b.idrPicId
}

// One byte offset per access unit, and just enough codec state to compute display order.
#[Swag.NoCopy]
private struct AnnexIndex
{
    frames:      Array!{SampleEntry}
    probe:       Decoder
    sequence:    Array!{u8}
    pictureSet:  Array!{u8}
    firstHeader: SliceHeader
    start:       u64
    group:       s64
    order:       s64
    hasPicture:  bool
    isReference: bool
}

impl AnnexIndex
{
    mtd read(source: *ByteSource) fail
    {
        var scanner: AnnexBScanner
        try scanner.open(source)

        var unit: AnnexBNal
        while try scanner.next(source, &unit)
        {
            if unit.payload - .start > MaxAnnexAccessUnit or unit.size > MaxAnnexAccessUnit
            {
                fail UnsupportedFormatError{"H.264 Annex B access unit exceeds the size limit"}
            }

            try source.seek(unit.payload)
            let nal  = try source.readByte()
            let kind = nal & 31
            if nal & 0x80
            {
                fail InvalidFormatError{"H.264 NAL unit has a set forbidden bit"}
            }

            // These units lead the next picture even if it carries no access unit delimiter.
            if .hasPicture and (kind == 6 or kind == 7 or kind == 8 or kind == 9)
            {
                try .finishPicture(unit.start)
            }

            switch kind
            {
            case 1, 5: try .readSlice(source, unit, nal)
            case 7:    try .readParameterSet(source, unit, &.sequence)
            case 8:    try .readParameterSet(source, unit, &.pictureSet)
            case 6, 9, 10, 11, 12: break
            case 0:    fail InvalidFormatError{"H.264 Annex B stream carries a reserved NAL header"}
            default:   fail UnsupportedFormatError{"H.264 Annex B stream carries an unsupported NAL type"}
            }
        }

        if .hasPicture
        {
            try .finishPicture(source.size())
        }

        if not .frames.count
        {
            fail InvalidFormatError{"H.264 Annex B stream has no coded picture"}
        }
    }

    private mtd readParameterSet(source: *ByteSource, unit: AnnexBNal, stored: *Array!{u8}) fail
    {
        if unit.size > Swag.U16.Max
        {
            fail UnsupportedFormatError{"H.264 Annex B parameter set exceeds the configuration size limit"}
        }

        try source.seek(unit.payload)
        let bytes = try source.peek(unit.size)
        let nal   = bytes[until unit.size]
        if stored.count
        {
            if stored.count != nal.count or Memory.compare(stored.storage() + 1, nal.buffer + 1, nal.count - 1) != 0
            {
                fail UnsupportedFormatError{"H.264 Annex B stream changes its parameter sets"}
            }

            return
        }

        try .probe.readParameterSet(nal, readVuiTiming: true)
        stored.add(nal)
    }

    private mtd readSlice(source: *ByteSource, unit: AnnexBNal, nal: u8) fail
    {
        let refIdc      = cast(u32, nal) >> 5
        let isIdr       = (nal & 31) == 5
        let isReference = refIdc != 0
        if isIdr and not isReference
        {
            fail InvalidFormatError{"H.264 IDR picture has a non-reference NAL header"}
        }

        let size  = Math.min(unit.size - 1, MaxAnnexSliceHeader)
        let bytes = try source.peek(size)
        unescapeRbsp(&.probe.rbsp, bytes[until size])

        .probe.markingParsed = false
        .probe.mmcoOps.clear()
        var slice: Slice
        if not (try slice.parseHeader(&.probe, refIdc, isIdr))
        {
            return
        }

        if .hasPicture and samePicture(.firstHeader, slice.header, .isReference, isReference)
        {
            return
        }

        if .hasPicture
        {
            try .finishPicture(unit.start)
        }

        if not .frames.count and not isIdr
        {
            fail UnsupportedFormatError{"H.264 Annex B stream must start with an IDR picture"}
        }

        if .frames.count and slice.header.noPriorOutput
        {
            fail UnsupportedFormatError{"H.264 Annex B stream suppresses earlier pictures at an IDR"}
        }

        for operation in .probe.mmcoOps where operation.op == 5
        {
            fail UnsupportedFormatError{"H.264 Annex B stream resets picture order outside an IDR"}
        }

        if isIdr and .frames.count
        {
            .group += 1
        }

        .probe.isRefPicture = isReference
        let poc = .probe.computePoc(&slice.header)

        // POC restarts at an IDR and may be negative. Each IDR group covers the
        // complete signed range, so no POC in one group sorts into another.
        .order       = .group * (1_s64 << 32) + cast(s64, poc)
        .firstHeader = slice.header
        .isReference = isReference
        .hasPicture  = true
    }

    private mtd finishPicture(end: u64) fail
    {
        let size = end - .start
        if size > MaxAnnexAccessUnit
        {
            fail UnsupportedFormatError{"H.264 Annex B access unit exceeds the size limit"}
        }

        if .frames.count == MaxAnnexFrames
        {
            fail UnsupportedFormatError{"H.264 Annex B stream exceeds 1048576 pictures"}
        }

        .frames.add({.start, size, .order, .firstHeader.isIdr})
        .start      = end
        .hasPicture = false
    }

    mtd configuration()->Array!{u8} fail
    {
        var bytes:     Array!{u8}
        let delimiter: [3] u8 = [0, 0, 1]
        bytes.add(delimiter)
        bytes.add(.sequence.toSlice())
        bytes.add(delimiter)
        bytes.add(.pictureSet.toSlice())
        var initial = try AnnexBAccessUnit.parse(bytes.toSlice())
        return #move initial.decoderConfig
    }
}

#[Swag.NoCopy]
struct AnnexBReader
{
    stream: AvcStream
}

impl IDecoder for AnnexBReader
{
    mtd impl format()->StreamFormat => {"H.264 Annex B elementary stream", ".h264;.264"}

    mtd impl open(source: *ByteSource)->StreamInfo fail
    {
        var index: AnnexIndex
        try index.read(source)
        let config = try index.configuration()
        let sps    = unwrap index.probe.firstSps()
        let rate   = sps.frameRate.isValid() ? sps.frameRate : (try FrameRate.create(25, 1))

        .stream.readsAnnexB = true
        try .stream.open(config.toSlice(), #move index.frames)
        let display = pictureDisplaySize(.stream.width, .stream.height, .stream.sampleAspectWidth, .stream.sampleAspectHeight)
        return {
            width: .stream.width,
            height: .stream.height,
            displayWidth: display.width,
            displayHeight: display.height,
            codecName: "H.264 / AVC",
            frameRate: rate,
            frameCount: .stream.frames.count}
    }

    mtd impl seekFrame(_: *ByteSource, index: u64) fail
    {
        if index >= .stream.frames.count
        {
            fail BadParameterError{"H.264 Annex B frame index exceeds the frame count"}
        }

        .stream.seekTo(index)
    }

    mtd impl decodeFrame(source: *ByteSource, target: *Image) fail => try .stream.decodeNext(source, target)
    mtd impl syncFrameAt(index: u64)->u64 => .stream.syncRankAt(index)
}

impl IPlanarDecoder for AnnexBReader
{
    mtd impl hasPlanarFrames()->bool => true
    mtd impl decodeFramePlanes(source: *ByteSource, target: *PlanarFrame) fail => try .stream.decodeNextPlanes(source, target)
}

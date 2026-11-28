//! Format: H.265/HEVC Annex B elementary byte stream.
//! Supported: Progressive Main and Main 10 pictures, stable parameter sets, multiple slices, picture reordering, and IDR seeks.
//! Not supported: Open groups of pictures, picture output suppression, and parameter-set changes.
//! Role: This file indexes byte ranges and feeds the HEVC picture stream.
//
#global namespace Hevc
#global internal

using Core, Core.Errors, Pixel

// The fields through POC occupy at most 64 bits with the decoder's parameter limits.
private const MaxAnnexPictureHeader = 16_u64

#[Swag.NoCopy]
private struct AnnexIndex
{
    frames:        Array!{SampleEntry}
    probe:         Decoder
    videoSet:      Array!{u8}
    sequence:      Array!{u8}
    pictureSet:    Array!{u8}
    rate:          FrameRate
    start:         u64
    group:         s64
    order:         s64
    nalType:       u32
    temporalId:    u32
    hasPicture:    bool
    endedSequence: bool
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
            try .readUnit(source, unit)
            if unit.payload + unit.size - .start > MaxAnnexAccessUnit
            {
                fail UnsupportedFormatError{"H.265 Annex B access unit exceeds the size limit"}
            }
        }

        if .hasPicture
        {
            try .finishPicture(source.size())
        }

        if not .frames.count
        {
            fail InvalidFormatError{"H.265 Annex B stream has no coded picture"}
        }
    }

    private mtd readUnit(source: *ByteSource, unit: AnnexBNal) fail
    {
        if unit.size < 3
        {
            fail InvalidFormatError{"H.265 Annex B NAL unit is truncated"}
        }

        if unit.size > MaxAnnexAccessUnit
        {
            fail UnsupportedFormatError{"H.265 Annex B NAL unit exceeds the size limit"}
        }

        try source.seek(unit.payload)
        let first  = try source.readByte()
        let second = try source.readByte()
        if first & 0x80 or not (second & 7)
        {
            fail InvalidFormatError{"H.265 Annex B NAL header is invalid"}
        }

        if first & 1 or second >> 3
        {
            fail UnsupportedFormatError{"H.265 Annex B stream uses more than one layer"}
        }

        let kind = cast(u32, (first >> 1))
        if .hasPicture and (kind == NalVps or kind == NalSps or kind == NalPps or kind == NalAud or kind == NalPrefixSei)
        {
            try .finishPicture(unit.start)
        }

        if isVideoCodingNal(kind)
        {
            try .readSlice(source, unit, kind, cast(u32, (second & 7)) - 1)
            return
        }

        switch kind
        {
        case NalVps:         try .readParameterSet(source, unit, kind, &.videoSet)
        case NalSps:         try .readParameterSet(source, unit, kind, &.sequence)
        case NalPps:         try .readParameterSet(source, unit, kind, &.pictureSet)
        case NalEos, NalEob: .endedSequence = true
        case NalAud, NalFillerData, NalPrefixSei, NalSuffixSei: break
        default:             fail UnsupportedFormatError{"H.265 Annex B stream carries an unsupported NAL type"}
        }
    }

    private mtd readParameterSet(source: *ByteSource, unit: AnnexBNal, kind: u32, stored: *Array!{u8}) fail
    {
        if unit.size > Swag.U16.Max
        {
            fail UnsupportedFormatError{"H.265 Annex B parameter set exceeds the configuration size limit"}
        }

        try source.seek(unit.payload)
        let bytes = try source.peek(unit.size)
        let nal   = bytes[until unit.size]
        if stored.count
        {
            if stored.count != nal.count or Memory.compare(stored.storage() + 2, nal.buffer + 2, nal.count - 2) != 0
            {
                fail UnsupportedFormatError{"H.265 Annex B stream changes its parameter sets"}
            }

            return
        }

        try .probe.readParameterSet(kind, nal[2 until nal.count])
        stored.add(nal)
    }

    private mtd readSlice(source: *ByteSource, unit: AnnexBNal, kind, temporal: u32) fail
    {
        let idr = isIdrNal(kind)

        // TSA and STSA pictures stay within the group. RADL, RASL, CRA and BLA may
        // lead or cross its IDR display boundary, which this fixed index avoids.
        if kind > 5 and not idr
        {
            fail UnsupportedFormatError{"H.265 Annex B stream requires closed IDR groups"}
        }

        if idr and temporal
        {
            fail InvalidFormatError{"H.265 Annex B IDR has a nonzero temporal ID"}
        }

        if not .videoSet.count or not .sequence.count or not .pictureSet.count
        {
            fail InvalidFormatError{"H.265 Annex B picture requires VPS, SPS and PPS before its slices"}
        }

        let size  = Math.min(unit.size - 2, MaxAnnexPictureHeader)
        let bytes = try source.peek(size)
        unescapeRbsp(&.probe.rbsp, bytes[until size])

        var reader: BitReader
        reader.init(.probe.rbsp.toSlice())
        let first   = reader.bit() != 0
        let noPrior = idr and reader.bit() != 0
        let ppsId   = reader.ue()
        if reader.overran or ppsId >= 64 or not .probe.pps[ppsId].valid
        {
            fail InvalidFormatError{"H.265 Annex B slice has a missing or invalid picture parameter set"}
        }

        if not first
        {
            if not .hasPicture or .endedSequence or kind != .nalType or temporal != .temporalId
            {
                fail InvalidFormatError{"H.265 Annex B slice continues a different picture"}
            }

            return
        }

        if .hasPicture
        {
            try .finishPicture(unit.start)
        }

        if (not .frames.count or .endedSequence) and not idr
        {
            fail UnsupportedFormatError{"H.265 Annex B sequence must start with an IDR picture"}
        }

        if .frames.count and noPrior
        {
            fail UnsupportedFormatError{"H.265 Annex B IDR suppresses earlier pictures"}
        }

        let pps    = &.probe.pps[ppsId]
        let sps    = unwrap .probe.sequenceOf(pps)
        let fields = try readSlicePictureFields(&reader, sps, pps, kind)
        if reader.overran
        {
            fail InvalidFormatError{"H.265 Annex B slice header is truncated"}
        }

        if not fields.output
        {
            fail UnsupportedFormatError{"H.265 Annex B stream suppresses a picture"}
        }

        if not .frames.count
        {
            if sps.vpsId != cast(u32, (.videoSet[2] >> 4))
            {
                fail InvalidFormatError{"H.265 Annex B sequence names a video parameter set that was not received"}
            }

            if sps.fieldSequence
            {
                fail UnsupportedFormatError{"H.265 Annex B stream carries field pictures"}
            }

            .rate = try nominalFrameRate(sps)
        }

        if idr and .frames.count
        {
            .group += 1
        }

        .probe.updatePictureOrder(kind, temporal, fields.pocLsb, sps)
        if not idr and .probe.pocValue <= 0
        {
            fail InvalidFormatError{"H.265 Annex B trailing picture has a nonpositive order count"}
        }

        // IDRs restart POC at zero. The group prefix leaves the entire signed
        // POC range so decode order and display order can differ within a group.
        .order         = .group * (1_s64 << 32) + cast(s64, .probe.pocValue)
        .nalType       = kind
        .temporalId    = temporal
        .hasPicture    = true
        .endedSequence = false
    }

    private mtd finishPicture(end: u64) fail
    {
        let size = end - .start
        if size > MaxAnnexAccessUnit or .frames.count == MaxAnnexFrames
        {
            fail UnsupportedFormatError{"H.265 Annex B index exceeds the decoder limits"}
        }

        .frames.add({.start, size, .order, isIdrNal(.nalType)})
        .start      = end
        .hasPicture = false
    }

    mtd const configuration()->Array!{u8}
    {
        var bytes: Array!{u8}
        appendAnnexNal(&bytes, .videoSet.toSlice())
        appendAnnexNal(&bytes, .sequence.toSlice())
        appendAnnexNal(&bytes, .pictureSet.toSlice())
        return bytes
    }
}

private func nominalFrameRate(sps: const *Sps)->FrameRate fail
{
    if not sps.vuiTimingPresent
    {
        return try FrameRate.create(25, 1)
    }

    let scale = cast(u64, sps.vuiTimeScale)
    let ticks = sps.vuiTicksPerPicture
    if not scale or not ticks
    {
        fail InvalidFormatError{"H.265 Annex B sequence set has invalid VUI timing"}
    }

    let divisor = cast(u64, try Math.gcd(cast(s64, scale), cast(s64, (ticks % scale))))
    if ticks / divisor > Swag.U32.Max
    {
        fail UnsupportedFormatError{"H.265 VUI rate exceeds the frame-rate range"}
    }

    return try FrameRate.create(cast(u32, (scale / divisor)), cast(u32, (ticks / divisor)))
}

#[Swag.NoCopy]
struct AnnexBReader
{
    stream: HevcStream
}

impl IDecoder for AnnexBReader
{
    mtd impl format()->StreamFormat => {"H.265 Annex B elementary stream", ".hevc;.h265"}

    mtd impl open(source: *ByteSource)->StreamInfo fail
    {
        var index: AnnexIndex
        try index.read(source)
        let config = index.configuration()
        try .stream.open(config.toSlice(), #move index.frames, readsAnnexB: true)
        let display = pictureDisplaySize(.stream.width, .stream.height, .stream.sampleAspectWidth, .stream.sampleAspectHeight)
        return {
            width: .stream.width,
            height: .stream.height,
            displayWidth: display.width,
            displayHeight: display.height,
            codecName: "H.265 / HEVC",
            frameRate: index.rate,
            frameCount: .stream.frames.count}
    }

    mtd impl seekFrame(_: *ByteSource, index: u64) fail
    {
        if index >= .stream.frames.count
        {
            fail BadParameterError{"H.265 Annex B frame index exceeds the frame count"}
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

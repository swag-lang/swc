//! Format: ISO Base Media File Format (MP4) fragmented packet copy.
//! Supported: Key-frame-aligned H.264 ranges copied with optional AAC-LC tracks and bounded audio rounding.
//! Not supported: Metadata, sample-exact AAC cuts, open GOPs crossing a cut, and negative rebased presentation times.
//! Role: This file joins retained encoded packet ranges into a new fragmented MP4.
//
#global namespace Mp4
#global export

using Core, Core.Errors

// Selects a half-open range of video packets in decode order.
//
// The first packet and the packet just after the range must be key frames, unless the range reaches
// the end of the source. Ranges passed to [[Video.Mp4.copyVideoRanges]] or
// [[Video.Mp4.copyRanges]] must be ordered and separate.
struct VideoPacketRange
{
    public firstPacket:     u64     // Zero-based first packet to keep.
    public afterLastPacket: u64     // First packet to omit after this range.
}

private struct ValidatedVideoRange
{
    firstPacket:     u64
    afterLastPacket: u64
    sourceStart:     u64
    sourceEnd:       u64
    outputStart:     u64
}

private struct AudioCopySpan
{
    firstPacket: u64
    packetCount: u64
    outputStart: u64
}

private struct AudioCopyState
{
    nextOutput:       u64
    lastSourcePacket: u64
    hasOutput:        bool
}

private struct AudioTrackSummary
{
    firstTime:   u64
    packetCount: u64
}

private struct ProgressiveCopyPlan
{
    ranges: Array'ValidatedVideoRange
    audio:  Array'AudioTrackSummary
}

// Copies retained video ranges from a fragmented H.264 MP4 into a new video-only MP4.
//
// Packets and AVC configuration are copied unchanged; decode and presentation timestamps are
// rebased so the retained ranges meet. The source may contain AAC tracks, which are omitted from
// the output. Ranges must start and end on key frames, be ordered, and preserve presentation order
// within their decode-time span. The destination is replaced only after a complete file has been
// written to a temporary peer; the source and destination may be the same path. A failure leaves
// the previous destination in place. Validation scans fragment headers once; copying scans them
// again. Memory holds the requested ranges, one fragment, one encoded payload, and the writer's
// buffering limits, independent of the source recording's duration.
func copyVideoRanges(sourceFileName, targetFileName: string, ranges: const [..] VideoPacketRange, options: FragmentedOptions = {}) fail
{
    var source = try FragmentedPacketCursor.open(sourceFileName)
    let plan   = try planProgressiveVideoRanges(sourceFileName, ranges)

    let temporary     = Format.toString("%.swag-cut-%.tmp", targetFileName, Guid128.random())
    var ownsTemporary = true
    defer
    {
        if ownsTemporary do
            discard catch File.delete(temporary)
    }

    scope
    {
        var writer     = try FragmentedWriter.create(temporary, source.width(), source.height(), source.timescale(), source.avcConfig(), options)
        var bytes:  Array'u8
        var packet: FragmentedCursorPacket
        var videoIndex = 0'u64
        var rangeIndex = 0'u64
        while rangeIndex < plan.ranges.count and try source.nextPacket(&packet)
        {
            if not packet.isVideo do
                continue
            let range = plan.ranges[rangeIndex]
            if videoIndex >= range.firstPacket and videoIndex < range.afterLastPacket
            {
                let times = try rebasedVideoTime(packet.info, range.sourceStart, range.outputStart)
                try source.readPayload(packet, &bytes)
                try writer.addPacket(EncodedPacket{bytes.toSlice(), times.decodeTime, times.presentationTime,
                                                   packet.info.duration, packet.info.isKeyFrame})
            }

            videoIndex += 1
            if videoIndex == range.afterLastPacket do
                rangeIndex += 1
        }

        try writer.end()
    }

    source.close()
    try File.move(targetFileName, temporary)
    ownsTemporary = false
}

private func planProgressiveVideoRanges(fileName: string, ranges: const [..] VideoPacketRange)->ProgressiveCopyPlan fail
{
    if not ranges.count do
        fail BadParameterError{"fragmented MP4 copy needs at least one video range"}
    var previousEnd = 0'u64
    for range in ranges
    {
        if range.firstPacket < previousEnd or range.firstPacket >= range.afterLastPacket do
            fail BadParameterError{"fragmented MP4 video ranges are empty or overlapping"}
        previousEnd = range.afterLastPacket
    }

    var source = try FragmentedPacketCursor.open(fileName)
    var result: #returntype
    result.ranges.reserve(ranges.count)
    result.audio.resize(source.audioTrackCount())
    var packet: FragmentedCursorPacket
    var videoIndex    = 0'u64
    var rangeIndex    = 0'u64
    var outputBase    = 0'u64
    var sourceStart   = 0'u64
    var maxPresentEnd = 0'u64
    var completedEnd  = 0'u64
    var hasCompleted  = false
    while try source.nextPacket(&packet)
    {
        if not packet.isVideo
        {
            let track = &result.audio[packet.trackIndex]
            if not track.packetCount do
                track.firstTime = packet.info.decodeTime
            track.packetCount += 1
            continue
        }

        let info = packet.info
        if hasCompleted and videoIndex == completedEnd and not info.isKeyFrame do
            fail BadParameterError{"fragmented MP4 video range must end before a key frame"}
        if rangeIndex < ranges.count
        {
            let range = ranges[rangeIndex]
            if videoIndex == range.firstPacket
            {
                if not info.isKeyFrame do
                    fail BadParameterError{"fragmented MP4 video range must start at a key frame"}
                sourceStart   = info.decodeTime
                maxPresentEnd = 0
            }

            if videoIndex >= range.firstPacket and videoIndex < range.afterLastPacket
            {
                if info.decodeTime < sourceStart or
                   info.presentationTime < 0 or
                   cast(u64, info.presentationTime) < sourceStart or
                   info.duration > Swag.U64.Max - cast(u64, info.presentationTime) do
                    fail UnsupportedFormatError{"fragmented MP4 range crosses a presentation dependency"}
                maxPresentEnd = Math.max(maxPresentEnd, cast(u64, info.presentationTime) + info.duration)
                discard try rebasedVideoTime(info, sourceStart, outputBase)
                if videoIndex + 1 == range.afterLastPacket
                {
                    if info.decodeTime > Swag.U64.Max - info.duration do
                        fail OverflowError{"fragmented MP4 video range end overflows"}
                    let sourceEnd = info.decodeTime + info.duration
                    if maxPresentEnd > sourceEnd do
                        fail UnsupportedFormatError{"fragmented MP4 range crosses a presentation dependency"}
                    if sourceEnd < sourceStart or sourceEnd - sourceStart > Swag.U64.Max - outputBase do
                        fail OverflowError{"fragmented MP4 rebased video duration overflows"}
                    result.ranges.add({range.firstPacket, range.afterLastPacket, sourceStart, sourceEnd, outputBase})
                    outputBase   += sourceEnd - sourceStart
                    completedEnd = range.afterLastPacket
                    hasCompleted = true
                    rangeIndex   += 1
                }
            }
        }

        videoIndex += 1
    }

    if rangeIndex != ranges.count do
        fail BadParameterError{"fragmented MP4 video ranges are outside the source"}
    return result
}

// Copies key-frame-aligned H.264 ranges with every AAC-LC track from a fragmented MP4.
//
// Video packets remain byte-identical and their clocks are joined exactly. AAC packets also stay
// byte-identical; cut boundaries are rounded to whole 1024-sample access units. Rounding uses the
// cumulative output time, so it does not drift with the number of cuts. Where a source track
// covers a cut, the first selected AAC packet may start up to half an access unit from its source
// boundary. While sound remains available, the output audio end stays within half an access unit
// of the video end; a source track that ends early remains shorter. Whole AAC packets can include
// sound just outside a requested range. Empty or late-starting audio tracks remain separate. The
// destination is replaced only after the copy completes. Validation scans fragment headers;
// copying scans them again. Memory holds the requested ranges and tracks, one fragment, one
// encoded payload, and the writer's buffering limits, independent of recording duration.
func copyRanges(sourceFileName, targetFileName: string, ranges: const [..] VideoPacketRange, options: FragmentedOptions = {}) fail
{
    var source = try FragmentedPacketCursor.open(sourceFileName)
    let plan   = try planProgressiveVideoRanges(sourceFileName, ranges)
    let audio  = try planAudioRanges(&source, plan.ranges.toSlice(), plan.audio.toSlice())
    var configs: Array'FragmentedAudioConfig
    for trackIndex in source.audioTrackCount()
    {
        let track = try source.audioTrack(trackIndex)
        configs.add({track.sampleRate, track.channelCount, track.decoderConfig})
    }

    let temporary     = Format.toString("%.swag-cut-%.tmp", targetFileName, Guid128.random())
    var ownsTemporary = true
    defer
    {
        if ownsTemporary do
            discard catch File.delete(temporary)
    }

    scope
    {
        var writer     = try createCopyWriter(temporary, &source, configs.toSlice(), options)
        var bytes:        Array'u8
        var packet:       FragmentedCursorPacket
        var videoIndex = 0'u64
        var rangeIndex = 0'u64
        var audioIndices: Array'u64
        var audioRanges:  Array'u64
        audioIndices.resize(source.audioTrackCount())
        audioRanges.resize(source.audioTrackCount())
        while try source.nextPacket(&packet)
        {
            if packet.isVideo
            {
                if rangeIndex < plan.ranges.count
                {
                    let range = plan.ranges[rangeIndex]
                    if videoIndex >= range.firstPacket and videoIndex < range.afterLastPacket
                    {
                        let times = try rebasedVideoTime(packet.info, range.sourceStart, range.outputStart)
                        try source.readPayload(packet, &bytes)
                        try writer.addPacket(EncodedPacket{bytes.toSlice(), times.decodeTime, times.presentationTime,
                                                           packet.info.duration, packet.info.isKeyFrame})
                    }

                    if videoIndex + 1 == range.afterLastPacket do
                        rangeIndex += 1
                }

                videoIndex += 1
                continue
            }

            let trackIndex = packet.trackIndex
            let index      = audioIndices[trackIndex]
            while audioRanges[trackIndex] < plan.ranges.count
            {
                let span = audio[audioRanges[trackIndex] * source.audioTrackCount() + trackIndex]
                if index < span.firstPacket + span.packetCount do
                    break
                audioRanges[trackIndex] += 1
            }

            if audioRanges[trackIndex] < plan.ranges.count
            {
                let span = audio[audioRanges[trackIndex] * source.audioTrackCount() + trackIndex]
                if index >= span.firstPacket
                {
                    let time = span.outputStart + (index - span.firstPacket) * 1024
                    try source.readPayload(packet, &bytes)
                    try writer.addAudioPacket(EncodedPacket{bytes.toSlice(), time, time, 1024, true}, trackIndex)
                }
            }

            audioIndices[trackIndex] += 1
        }

        try writer.end()
    }

    source.close()
    try File.move(targetFileName, temporary)
    ownsTemporary = false
}

private func createCopyWriter(path: string, source: *FragmentedPacketCursor, audioTracks: const [..] FragmentedAudioConfig, options: FragmentedOptions)->FragmentedWriter fail
{
    if audioTracks.count do
        return try FragmentedWriter.createWithAudioTracks(path, source.width(), source.height(), source.timescale(), source.avcConfig(), audioTracks, options)
    return try FragmentedWriter.create(path, source.width(), source.height(), source.timescale(), source.avcConfig(), options)
}

private func planAudioRanges(source: *FragmentedPacketCursor, ranges: const [..] ValidatedVideoRange, summaries: const [..] AudioTrackSummary)->Array'AudioCopySpan fail
{
    var result: #returntype
    let trackCount = source.audioTrackCount()
    result.reserve(ranges.count * trackCount)
    var states: Array'AudioCopyState
    states.resize(trackCount)
    for range in ranges
    {
        let videoEnd = range.outputStart + (range.sourceEnd - range.sourceStart)
        for trackIndex in trackCount
        {
            let track   = try source.audioTrack(trackIndex)
            let summary = summaries[trackIndex]
            var span: AudioCopySpan
            if not summary.packetCount
            {
                result.add(span)
                continue
            }

            let audioTimebase = try Timebase.create(track.sampleRate)
            let inputStart    = try audioTimebase.convertFrom(range.sourceStart, source.timescale())
            let inputEnd      = try audioTimebase.convertFrom(range.sourceEnd, source.timescale())
            let outputStart   = try audioTimebase.convertFrom(range.outputStart, source.timescale())
            let outputEnd     = try audioTimebase.convertFrom(videoEnd, source.timescale())
            let firstTime     = summary.firstTime
            var firstIndex    = 0'u64
            if inputStart > firstTime
            {
                let delta = inputStart - firstTime
                firstIndex = delta / 1024 + cast(u64, delta % 1024 >= 512)
            }

            if states[trackIndex].hasOutput and firstIndex <= states[trackIndex].lastSourcePacket do
                firstIndex = states[trackIndex].lastSourcePacket + 1
            if firstIndex >= summary.packetCount
            {
                result.add(span)
                continue
            }

            let selectedTime = firstTime + firstIndex * 1024
            if selectedTime >= inputEnd and selectedTime - inputEnd >= 512
            {
                result.add(span)
                continue
            }

            var nextOutput = states[trackIndex].nextOutput
            if not states[trackIndex].hasOutput
            {
                let delay = selectedTime > inputStart ? selectedTime - inputStart : 0
                if delay > Swag.U64.Max - outputStart do
                    fail OverflowError{"fragmented MP4 audio start overflows"}
                nextOutput = outputStart + delay
            }

            if nextOutput >= outputEnd
            {
                result.add(span)
                continue
            }

            let wanted = outputEnd - nextOutput
            var count  = wanted / 1024 + cast(u64, wanted % 1024 >= 512)
            count = Math.min(count, summary.packetCount - firstIndex)
            for offset in count
            {
                let time = selectedTime + offset * 1024
                if time >= inputEnd and time - inputEnd >= 512
                {
                    count = offset
                    break
                }
            }

            if not count
            {
                result.add(span)
                continue
            }

            if nextOutput > cast(u64, Swag.S64.Max) or
               count > (cast(u64, Swag.S64.Max) - nextOutput) / 1024 do
                fail OverflowError{"fragmented MP4 rebased AAC time exceeds its supported range"}
            span = {firstIndex, count, nextOutput}
            states[trackIndex].nextOutput       = nextOutput + count * 1024
            states[trackIndex].lastSourcePacket = firstIndex + count - 1
            states[trackIndex].hasOutput        = true
            result.add(span)
        }
    }

    return result
}

private func rebasedVideoTime(packet: FragmentedPacketInfo, sourceStart, outputBase: u64)->{decodeTime: u64, presentationTime: u64} fail
{
    let decodeDelta       = packet.decodeTime - sourceStart
    let presentationDelta = cast(u64, packet.presentationTime) - sourceStart
    if decodeDelta > Swag.U64.Max - outputBase or presentationDelta > Swag.U64.Max - outputBase do
        fail OverflowError{"fragmented MP4 rebased video timestamp overflows"}
    let decodeTime       = outputBase + decodeDelta
    let presentationTime = outputBase + presentationDelta
    if decodeTime > cast(u64, Swag.S64.Max) or presentationTime > cast(u64, Swag.S64.Max) do
        fail UnsupportedFormatError{"fragmented MP4 rebased video time exceeds its composition range"}
    return {decodeTime, presentationTime}
}

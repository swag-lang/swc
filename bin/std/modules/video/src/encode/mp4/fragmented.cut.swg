//! Format: ISO Base Media File Format (MP4) fragmented video packet copy.
//! Supported: Key-frame-aligned H.264 ranges copied without decoding or re-encoding.
//! Not supported: Audio or metadata in the output, open GOPs crossing a cut, and negative rebased presentation times.
//! Role: This file joins retained video packet ranges into a new fragmented MP4.
//
#global namespace Mp4
#global export

using Core, Core.Errors

// Selects a half-open range of video packets in decode order.
//
// The first packet and the packet just after the range must be key frames, unless the range reaches
// the end of the source. Ranges passed to [[Video.Mp4.copyVideoRanges]] must be ordered and separate.
struct VideoPacketRange
{
    public firstPacket:     u64     // Zero-based first packet to keep.
    public afterLastPacket: u64     // First packet to omit after this range.
}

// Copies retained video ranges from a fragmented H.264 MP4 into a new video-only MP4.
//
// Packets and AVC configuration are copied unchanged; decode and presentation timestamps are
// rebased so the retained ranges meet. The source may contain AAC tracks, which are omitted from
// the output. Ranges must start and end on key frames, be ordered, and preserve presentation order
// within their decode-time span. The destination is replaced only after a complete file has been
// written to a temporary peer; the source and destination may be the same path. A failure leaves
// the previous destination in place. Memory use is bounded by one encoded packet and writer limits.
func copyVideoRanges(sourceFileName, targetFileName: string, ranges: const [..] VideoPacketRange, options: FragmentedOptions = {}) fail
{
    if not ranges.count do
        fail BadParameterError{"fragmented MP4 copy needs at least one video range"}
    var source      = try FragmentedPacketReader.open(sourceFileName)
    var outputBase  = 0'u64
    var previousEnd = 0'u64
    for range in ranges
    {
        if range.firstPacket < previousEnd or
           range.firstPacket >= range.afterLastPacket or
           range.afterLastPacket > source.packetCount() do
            fail BadParameterError{"fragmented MP4 video ranges are empty, overlapping, or outside the source"}
        let first = try source.packetInfo(range.firstPacket)
        if not first.isKeyFrame do
            fail BadParameterError{"fragmented MP4 video range must start at a key frame"}
        if range.afterLastPacket < source.packetCount() and
           not (try source.packetInfo(range.afterLastPacket)).isKeyFrame do
            fail BadParameterError{"fragmented MP4 video range must end before a key frame"}

        let last = try source.packetInfo(range.afterLastPacket - 1)
        if last.decodeTime > Swag.U64.Max - last.duration do
            fail OverflowError{"fragmented MP4 video range end overflows"}
        let sourceEnd = last.decodeTime + last.duration
        if sourceEnd < first.decodeTime or sourceEnd - first.decodeTime > Swag.U64.Max - outputBase do
            fail OverflowError{"fragmented MP4 rebased video duration overflows"}

        for index in range.firstPacket until range.afterLastPacket
        {
            let packet = try source.packetInfo(index)
            if packet.decodeTime < first.decodeTime or
               packet.presentationTime < 0 or
               cast(u64, packet.presentationTime) < first.decodeTime or
               packet.duration > sourceEnd or
               cast(u64, packet.presentationTime) > sourceEnd - packet.duration do
                fail UnsupportedFormatError{"fragmented MP4 range crosses a presentation dependency"}
            discard try rebasedVideoTime(packet, first.decodeTime, outputBase)
        }

        outputBase  += sourceEnd - first.decodeTime
        previousEnd = range.afterLastPacket
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
        var writer = try FragmentedWriter.create(temporary, source.width(), source.height(), source.timescale(), source.avcConfig(), options)
        var bytes: Array'u8
        outputBase = 0
        for range in ranges
        {
            let start = (try source.packetInfo(range.firstPacket)).decodeTime
            for index in range.firstPacket until range.afterLastPacket
            {
                let info   = try source.packetInfo(index)
                let times  = try rebasedVideoTime(info, start, outputBase)
                let packet = try source.readPacket(index, &bytes)
                try writer.addPacket(EncodedPacket{packet.bytes, times.decodeTime,
                                                   times.presentationTime, packet.duration,
                                                   packet.isKeyFrame})
            }

            let last = try source.packetInfo(range.afterLastPacket - 1)
            outputBase += last.decodeTime + last.duration - start
        }

        try writer.end()
    }

    source.close()
    try File.move(targetFileName, temporary)
    ownsTemporary = false
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

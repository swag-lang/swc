//! Format: Precise trimming of software H.264/AAC fragmented recordings.
//! Supported: Closed progressive GOPs matching the portable H.264 encoder and frame-aligned cuts.
//! Not supported: Reordered pictures, geometry/codec conversion, or late-starting sound at a cut.
//! Role: Encodes dependent boundaries and edited spans; copies unaffected video and AAC payloads.
//
#global namespace Mp4
#global export

using Core, Core.Errors, Pixel

// Reports work performed by [[Video.Mp4.trimSoftwareRecording]].
struct SoftwareTrimResult
{
    public copiedVideoFrames:  u64     // Retained original H.264 access units.
    public encodedVideoFrames: u64     // Pictures encoded for the first GOP, pixel edits and dependent tails.
    public copiedAudioPackets: u64     // Retained original AAC access units, including hidden decode preroll.
}

// Selects source pictures whose pixels must be rendered during a trim.
struct SoftwareRenderRange
{
    public firstFrame:     u64     // Zero-based first edited picture, inclusive.
    public afterLastFrame: u64     // First unedited picture after the range, exclusive.
}

// Replaces one decoded picture with its edited pixels; the image and index are borrowed.
//
// The callback runs synchronously on the calling thread and may fail. Keep the original geometry.
alias SoftwareFrameRenderer = func||(frameIndex: u64, image: *Image) fail

// Supplies timed pixel edits without forcing a full-recording transcode.
//
// Ranges may overlap and need not be ordered. They and the callback are borrowed for the call to
// [[Video.Mp4.trimSoftwareRecording]]. Each edited span starts an independently encoded passage;
// copying resumes at the next original IDR after the span ends.
struct SoftwareTrimEdits
{
    public ranges: const [..] SoftwareRenderRange = []     // Edited source-frame intervals.
    public render: SoftwareFrameRenderer?     // Required when at least one range is supplied.
}

private struct SoftwareTrimAudio
{
    firstTime:    u64
    endTime:      u64
    firstCopy:    u64
    afterCopy:    u64
    presentation: AudioPresentationRange
}

private struct SoftwareTrimPlan
{
    sourceStart:      u64
    sourceEnd:        u64
    firstVideoTime:   u64
    firstCopiedFrame: u64
    audio:            Array'SoftwareTrimAudio
}

// Trims a software H.264 recording precisely, copying its unchanged compressed interior.
//
// Keeps zero-based pictures in `[firstFrame, afterLastFrame)`. Their original durations and
// every available AAC track are retained. At most the dependent first GOP is decoded/encoded;
// copying resumes at its next IDR. `edits` also re-encodes only passages affected by pixel changes
// and their dependent tails. Audio packets include transform history, hidden by exact
// presentation edits. Players must honor those edits for sample-accurate sound boundaries.
//
// The AVC configuration must match [[Video.H264.Encoder]] and pictures must have equal decode
// and presentation times. Unsupported sources fail with [[Core.Errors.UnsupportedFormatError]];
// no approximate key-frame snapping is performed. Memory holds one GOP picture, bounded mux
// groups, the reader's indexes and one encoded packet, not all retained media.
// The destination is replaced atomically after completion; the original and a previous target
// survive failure. The source and target may name the same file.
//
// ## Example
//
// ```swag
// let work = try Video.Mp4.trimSoftwareRecording("recording.mp4", "excerpt.mp4", 31, 215_969)
// Core.Console.println("Pictures copied: ", work.copiedVideoFrames)
// ```
func trimSoftwareRecording(sourceFileName, targetFileName: string, firstFrame, afterLastFrame: u64, options: FragmentedOptions = {60, 4 * 1024 * 1024, 100, true}, edits: SoftwareTrimEdits = {})->SoftwareTrimResult fail
{
    if firstFrame >= afterLastFrame do
        fail BadParameterError{"software video trim needs a nonempty frame range"}
    var source = try FragmentedPacketCursor.open(sourceFileName)
    defer source.close()
    var encoder = try H264.Encoder.create(source.width(), source.height())
    if not Slice.equals(encoder.decoderConfig(), source.avcConfig()) do
        fail UnsupportedFormatError{"software video trim needs a compatible AVC configuration"}
    var plan   = try SoftwareTrimPlan.create(sourceFileName, firstFrame, afterLastFrame)
    var reader = try Reader.open(sourceFileName)
    defer reader.close()
    if edits.ranges.count and not edits.render do
        fail BadParameterError{"software video edits need a frame renderer"}
    for range in edits.ranges where range.firstFrame >= range.afterLastFrame or
                                    range.afterLastFrame > reader.frameCount() do
        fail BadParameterError{"software video edit range is outside the source"}
    var audioPlan = #move plan.audio
    var configs: Array'FragmentedAudioConfig
    for index in source.audioTrackCount()
    {
        let config = try source.audioTrack(index)
        configs.add({config.sampleRate, config.channelCount, config.decoderConfig})
        let track = &audioPlan[index]
        if not track.endTime do
            continue
        let clock = try Timebase.create(config.sampleRate)
        var start = try clock.convertFrom(plan.sourceStart, source.timescale())
        var end   = try clock.convertFrom(plan.sourceEnd, source.timescale())
        if start < track.firstTime do
            fail UnsupportedFormatError{"software video trim cannot rebase a late-starting audio track"}
        let sound = reader.audioTrack(cast(u32, index))
        if not sound do
            continue
        var available = track.endTime
        var edit: AudioPresentationRange
        if try source.tryAudioPresentationRange(index, &edit)
        {
            let relativeStart = try clock.convertFrom(plan.sourceStart - plan.firstVideoTime, source.timescale())
            let relativeEnd   = try clock.convertFrom(plan.sourceEnd - plan.firstVideoTime, source.timescale())
            if edit.firstSample > Swag.U64.Max - Math.max(relativeEnd, edit.sampleCount) do
                fail OverflowError{"software video trim audio range overflows"}
            start     = edit.firstSample + relativeStart
            end       = edit.firstSample + relativeEnd
            available = edit.firstSample + edit.sampleCount
        }
        else
        {
            let origin = try clock.convertFrom(plan.firstVideoTime, source.timescale())
            let delay  = cast(u64, Math.round(sound.timelineStartSeconds() * config.sampleRate))
            if origin > Swag.U64.Max - delay or origin + delay > Swag.U64.Max - sound.sampleFrameCount() do
                fail OverflowError{"software video trim audio range overflows"}
            available = origin + delay + sound.sampleFrameCount()
        }

        let finish = Math.min(Math.min(end, available), track.endTime)
        if start >= finish do
            continue
        let packet = (start - track.firstTime) / 1_024
        track.firstCopy = track.firstTime + (packet ? packet - 1 : 0) * 1_024
        let remaining = finish - track.firstTime
        let packets   = remaining / 1_024 + cast(u64, remaining % 1_024 != 0)
        track.afterCopy    = track.firstTime + packets * 1_024
        track.presentation = {start - track.firstCopy, finish - start}
    }

    let temporary     = Format.toString("%.swag-trim-%.tmp", targetFileName, Guid128.random())
    var ownsTemporary = true
    defer
    {
        if ownsTemporary do
            discard catch File.delete(temporary)
    }

    var result: #returntype
    scope
    {
        var writer: FragmentedWriter
        if configs.count do
            writer = try FragmentedWriter.createWithAudioTracks(temporary,
                                                                source.width(),
                                                                source.height(),
                                                                source.timescale(),
                                                                source.avcConfig(),
                                                                configs.toSlice(),
                                                                options)
        else do
            writer = try FragmentedWriter.create(temporary, source.width(), source.height(), source.timescale(), source.avcConfig(), options)
        var packet:  FragmentedCursorPacket
        var bytes:   Array'u8
        var picture: Image
        var nv12:    Nv12Frame
        var videoIndex = 0'u64
        var encoding   = firstFrame < plan.firstCopiedFrame
        while try source.nextPacket(&packet)
        {
            if packet.isVideo
            {
                let index = videoIndex
                videoIndex += 1
                if index < firstFrame or index >= afterLastFrame do
                    continue
                let time   = packet.info.decodeTime - plan.sourceStart
                var edited = false
                for range in edits.ranges where index >= range.firstFrame and index < range.afterLastFrame
                {
                    edited = true
                    break
                }

                if packet.info.isKeyFrame and not edited do
                    encoding = false
                if edited and not encoding
                {
                    encoder  = try H264.Encoder.create(source.width(), source.height())
                    encoding = true
                }

                if encoding
                {
                    try reader.decodeFrameInto(&picture, index)
                    if edited
                    {
                        let render = unwrap edits.render
                        try render(index, &picture)
                    }

                    try nv12.convertFrom(&picture)
                    try writer.addPacket(try encoder.encode(&nv12, time, packet.info.duration))
                    result.encodedVideoFrames += 1
                }
                else
                {
                    try source.readPayload(packet, &bytes)
                    try writer.addPacket({bytes.toSlice(), time, time, packet.info.duration, packet.info.isKeyFrame})
                    result.copiedVideoFrames += 1
                }
            }
            else
            {
                let track = &audioPlan[packet.trackIndex]
                let time  = packet.info.decodeTime
                if not track.presentation.sampleCount or
                   time < track.firstCopy or
                   time >= track.afterCopy do
                    continue
                try source.readPayload(packet, &bytes)
                try writer.addAudioPacket({bytes.toSlice(), time - track.firstCopy, time - track.firstCopy,
                                           packet.info.duration, true},
                                          packet.trackIndex)
                result.copiedAudioPackets += 1
            }
        }

        var ranges: Array'AudioPresentationRange
        for track in audioPlan do
            ranges.add(track.presentation)
        try writer.setPresentationEdits(0, ranges.toSlice())
        try writer.end()
    }

    reader.close()
    source.close()
    try File.move(targetFileName, temporary)
    ownsTemporary = false
    return result
}

private impl SoftwareTrimPlan
{
    func create(path: string, firstFrame, afterLastFrame: u64)->SoftwareTrimPlan fail
    {
        var source = try FragmentedPacketCursor.open(path)
        var result: #returntype
        result.audio.resize(source.audioTrackCount())
        result.firstCopiedFrame = afterLastFrame
        var packet: FragmentedCursorPacket
        var index = 0'u64
        while try source.nextPacket(&packet)
        {
            if packet.isVideo
            {
                if packet.info.presentationTime < 0 or
                   cast(u64, packet.info.presentationTime) != packet.info.decodeTime do
                    fail UnsupportedFormatError{"software video trim does not support reordered pictures"}
                if index == 0 do
                    result.firstVideoTime = packet.info.decodeTime
                if index == firstFrame do
                    result.sourceStart = packet.info.decodeTime
                if index >= firstFrame and index < result.firstCopiedFrame and packet.info.isKeyFrame do
                    result.firstCopiedFrame = index
                if index + 1 == afterLastFrame do
                    result.sourceEnd = packet.info.decodeTime + packet.info.duration
                index += 1
            }
            else
            {
                let track = &result.audio[packet.trackIndex]
                if not track.endTime do
                    track.firstTime = packet.info.decodeTime
                track.endTime = packet.info.decodeTime + packet.info.duration
            }
        }

        if afterLastFrame > index or not result.sourceEnd do
            fail BadParameterError{"software video trim frame range is outside the source"}
        return result
    }
}

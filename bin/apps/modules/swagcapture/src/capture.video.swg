using Core, Core.Errors, Gui, Pixel, Audio, Video

impl Capture
{
    // Places a standalone MP4 on the clipboard with the kept span and annotations.
    mtd copyVideo() fail
    {
        let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "Swag Capture")
        if not Directory.exists(folder) do
            try Directory.create(folder)

        let name = Format.toString("%-%.mp4",
                                   Path.fileNameWithoutExtension(.file) orelse "video",
                                   Guid128.random())
        let path = Path.combine(folder, name)
        try .exportVideo(path)

        var files: Array'String
        files.add(path)
        Clipboard.setFiles(files.toSlice())
    }

    // Writes the kept video span with its visible annotations and separate sound tracks.
    // The MP4 beside the capture document remains the unmodified recording.
    mtd exportVideo(path: string) fail
    {
        if .media != .Video or .mediaMissing or not .frames do
            fail InvalidFormatError{"the capture has no video to export"}

        let source = mediaPathOf(.file, .Video)
        let targetPath = try Path.absolute(path)
        let sourcePath = try Path.absolute(source)
        if Path.equals(targetPath, sourcePath) do
            fail BadParameterError{"choose another file for the exported video"}

        let frames = unwrap .frames
        let start  = .trimStart()
        let finish = .trimEnd()
        if finish <= start do
            fail BadParameterError{"the kept video span is empty"}

        // Publish only a complete MP4. A failed export leaves an earlier destination intact.
        let temporary = Format.toString("%.swag-export-%.tmp", path, Guid128.random())
        var ownsTemporary = true
        defer
        {
            if ownsTemporary do
                discard catch File.delete(temporary)
        }

        // A capture without edits keeps the original encoded picture and sound bytes.
        if .forms.isEmpty() and not .isTrimmed() and
           .width == frames.width and .height == frames.height
        {
            try File.duplicate(temporary, source)
            try File.move(path, temporary)
            ownsTemporary = false
            return
        }

        var input = try Reader.open(source)
        defer input.close()
        var audioConfigs: Array'Mp4.SoftwareAudioConfig
        for index in cast(u64, input.audioTrackCount())
        {
            let sound = unwrap input.audioTrack(cast(u32, index))
            let bandwidth = sound.numChannels() == 1 ? Aac.Bandwidth.Voice : Aac.Bandwidth.Full
            audioConfigs.add({sound.sampleRateHz(), cast(u16, sound.numChannels()), bandwidth})
        }

        let width  = .width + (.width % 2)
        let height = .height + (.height % 2)
        var recording = try Mp4.SoftwareRecording.createWithAudioTracks(
            temporary, width, height, 1_000_000, audioConfigs.toSlice())
        let playhead = .playhead
        defer catch .showFrame(playhead)

        var outputFrame: u64
        var outputTime:  u64
        for frame in frames.frameAt(start) until frames.frameCount()
        {
            let shown = Math.max(frames.timeOf(frame), start)
            if shown >= finish do
                break
            let next = frame + 1 < frames.frameCount() ? frames.timeOf(frame + 1) : frames.endTime
            if next <= shown do
                continue
            var remaining = Math.min(next, finish) - shown
            if not remaining do
                continue

            try .showFrame(frame)
            var image = .toImage()
            if not image.isValid() do
                fail InvalidFormatError{"the video frame could not be rendered"}
            if image.width != width or image.height != height
            {
                var padded = Image.create(width, height, .BGRA8)
                padded.fill(Argb.White)
                for row in cast(u64, image.height)
                {
                    Memory.copy(padded.pixels.storage() + row * cast(u64, padded.rowStride),
                                image.pixels.storage() + row * cast(u64, image.rowStride),
                                cast(u64, image.width) * 4)
                }
                image = #move padded
            }

            while remaining
            {
                let duration = cast(u32, Math.min(remaining, cast(u64, Swag.U32.Max)))
                try recording.addFrame(&image, FrameSlot{outputFrame, outputTime, duration, 0})
                outputFrame += 1
                outputTime += duration
                remaining -= duration
            }
        }

        if not outputFrame do
            fail InvalidFormatError{"the kept video span has no frame"}
        for index in cast(u64, input.audioTrackCount())
        {
            let trackIndex = cast(u32, index)
            let sound = unwrap input.audioTrack(trackIndex)
            try exportVideoSound(&recording, sound, start, finish, trackIndex)
        }
        try recording.end()
        try File.move(path, temporary)
        ownsTemporary = false
    }
}

// Streams only the kept sample range into one output AAC track, without retaining the sound in
// memory. A source ending before the video span leaves silence to its end.
private func exportVideoSound(recording: *Mp4.SoftwareRecording, sound: const *SoundFile,
                              start, finish: u64, trackIndex: u32) fail
{
    let rate     = cast(u64, sound.sampleRateHz())
    let channels = cast(u64, sound.numChannels())
    let from     = start * rate / 1_000_000
    let wanted   = (finish - start) * rate / 1_000_000
    let endSample = Math.min(from + wanted, sound.sampleFrameCount())
    var cursor:   u64
    var written:  u64
    var failure:  Swag.Error

    if from < endSample
    {
        try sound.decodePcm16(func|recording, trackIndex, from, endSample, channels,
                                   cursor = &cursor, written = &written,
                                   failure = &failure|(part: const [..] s16)->bool
        {
            let count = part.count / channels
            let first = Math.max(cursor[], from)
            let last  = Math.min(cursor[] + count, endSample)
            if last > first
            {
                let begin = (first - cursor[]) * channels
                catch recording.addAudioFrames(part[begin until begin + (last - first) * channels], trackIndex)
                {
                    failure.capture(Swag.err)
                    return false
                }
                written[] += last - first
            }
            cursor[] += count
            return cursor[] < endSample
        })
        if failure.value() do
            try failure.raise()
    }

    var zeros: [2 * 1_024] s16
    while written < wanted
    {
        let count = Math.min(wanted - written, 1_024'u64)
        try recording.addAudioFrames(Swag.makeSlice(&zeros[0], count * channels), trackIndex)
        written += count
    }
}

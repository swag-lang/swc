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

        let source     = mediaPathOf(.file, .Video)
        let targetPath = try Path.absolute(path)
        let sourcePath = try Path.absolute(source)
        if Path.equals(targetPath, sourcePath) do
            fail BadParameterError{"choose another file for the exported video"}

        let frames = .frames
        let start  = .trimStart()
        let finish = .trimEnd()
        if finish <= start do
            fail BadParameterError{"the kept video span is empty"}

        // Publish only a complete MP4. A failed export leaves an earlier destination intact.
        let temporary     = Format.toString("%.swag-export-%.tmp", path, Guid128.random())
        var ownsTemporary = true
        defer
        {
            if ownsTemporary do
                discard catch File.delete(temporary)
        }

        // A capture without edits keeps the original encoded picture and sound bytes.
        if .forms.isEmpty() and
           not .isTrimmed() and
           .width == frames.width and
           .height == frames.height
        {
            try File.duplicate(temporary, source)
            try File.move(path, temporary)
            ownsTemporary = false
            return
        }

        // Precise trims and timed annotations keep every unaffected compressed passage.
        // Unsupported imported formats retain the rendering path below; I/O errors do not.
        if .width == frames.width and .height == frames.height
        {
            let first = frames.frameAt(start)
            let after = finish >= frames.endTime ? frames.frameCount() : frames.frameAt(finish)
            if frames.timeOf(first) == start and
               (finish == frames.endTime or frames.timeOf(after) == finish)
            {
                var ranges: Array'Mp4.SoftwareRenderRange
                for form in .forms
                {
                    let begins = Math.max(start, form.timeStart)
                    let ends   = Math.min(finish, form.timeEnd ? form.timeEnd : frames.endTime)
                    if begins >= ends do
                        continue
                    var left = frames.frameAt(begins)
                    if frames.timeOf(left) < begins do
                        left += 1
                    var right = ends >= frames.endTime ? frames.frameCount() : frames.frameAt(ends)
                    if right < frames.frameCount() and frames.timeOf(right) < ends do
                        right += 1
                    if left < right do
                        ranges.add({left, right})
                }

                let renderer: Mp4.SoftwareFrameRenderer = func|capture = me|(frameIndex: u64, image: *Image) fail
                {
                    try capture.showFrame(frameIndex)
                    var edited = capture.toImage()
                    if not edited.isValid() do
                        fail InvalidFormatError{"the video frame could not be rendered"}
                    image[] = #move edited
                }

                let playhead = .playhead
                defer
                {
                    if ranges.count do
                        catch .showFrame(playhead)
                }

                var copied = false
                catch
                {
                    discard try Mp4.trimSoftwareRecording(source, temporary, first, after, edits: Mp4.SoftwareTrimEdits{ranges.toSlice(), renderer})
                    copied = true
                }
                {
                    if not (Swag.err is UnsupportedFormatError) do
                        fail Swag.err
                }

                if copied
                {
                    try File.move(path, temporary)
                    ownsTemporary = false
                    return
                }
            }
        }

        var input = try Reader.open(source)
        defer input.close()
        var audioConfigs: Array'Mp4.SoftwareAudioConfig
        for index in cast(u64, input.audioTrackCount())
        {
            let sound     = unwrap input.audioTrack(cast(u32, index))
            let bandwidth = sound.numChannels() == 1 ? Aac.Bandwidth.Voice : Aac.Bandwidth.Full
            audioConfigs.add({sound.sampleRateHz(), cast(u16, sound.numChannels()), bandwidth})
        }

        let width     = .width + (.width % 2)
        let height    = .height + (.height % 2)
        var recording = try Mp4.SoftwareRecording.createWithAudioTracks(temporary, width, height, 1_000_000, audioConfigs.toSlice())
        let playhead  = .playhead
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
                outputTime  += duration
                remaining   -= duration
            }
        }

        if not outputFrame do
            fail InvalidFormatError{"the kept video span has no frame"}
        for index in cast(u64, input.audioTrackCount())
        {
            let trackIndex = cast(u32, index)
            let sound      = unwrap input.audioTrack(trackIndex)
            try exportVideoSound(&recording, sound, start, finish, trackIndex)
        }

        try recording.end()
        try File.move(path, temporary)
        ownsTemporary = false
    }
}

// Streams only the kept sample range into one output AAC track, without retaining the sound in
// memory. A source ending before the video span leaves silence to its end.
private func exportVideoSound(recording: *Mp4.SoftwareRecording, sound: const *SoundFile, start, finish: u64, trackIndex: u32) fail
{
    let rate        = cast(u64, sound.sampleRateHz())
    let channels    = cast(u64, sound.numChannels())
    let sourceStart = cast(u64, Math.round(Math.max(sound.timelineStartSeconds(), 0) * 1_000_000))
    let from        = start > sourceStart ? (start - sourceStart) * rate / 1_000_000 : 0
    let wanted      = (finish - start) * rate / 1_000_000
    let leading     = sourceStart > start ? Math.min(wanted, (sourceStart - start) * rate / 1_000_000) : 0
    var written     = leading
    var failure: Swag.Error

    func writeSilence(recording: *Mp4.SoftwareRecording, track: u32, channels, count: u64) fail
    {
        var zeros: [2 * 1_024] s16
        var remaining = count
        while remaining
        {
            let frames = Math.min(remaining, 1_024'u64)
            try recording.addAudioFrames(Swag.makeSlice(&zeros[0], frames * channels), track)
            remaining -= frames
        }
    }

    try writeSilence(recording, trackIndex, channels, leading)
    if from < sound.sampleFrameCount() and written < wanted
    {
        let count  = Math.min(wanted - written, sound.sampleFrameCount() - from)
        let append = func|recording, trackIndex, channels, written = &written,
            failure = &failure|(part: const [..] s16)->bool
        {
            catch recording.addAudioFrames(part, trackIndex)
            {
                failure.capture(Swag.err)
                return false
            }

            written[] += part.count / channels
            return true
        }

        try sound.decodePcm16(from, count, append)
        if failure.value() do
            try failure.raise()
    }

    try writeSilence(recording, trackIndex, channels, wanted - written)
}

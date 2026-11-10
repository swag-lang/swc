impl Capture
{
    // Writes `time`, in microseconds, as minutes and two-digit seconds, with the hours in front past
    // an hour and the tenth of a second when `tenths` is set.
    func clockText(time: u64, tenths = false)->String
    {
        // `%%` is a literal percent sign in a format: two-digit fields are written digit by digit.
        func twoDigits(result: *String, value: u64)
        {
            result[] += Format.toString("%", value / 10)
            result[] += Format.toString("%", value % 10)
        }

        let seconds = time / 1_000_000
        var result: String
        if seconds >= 3600
        {
            result = Format.toString("%:", seconds / 3600)
            twoDigits(&result, (seconds / 60) % 60)
        }
        else
        {
            result = Format.toString("%", seconds / 60)
        }

        result += ":"
        twoDigits(&result, seconds % 60)
        if tenths do
            result += Format.toString(".%", (time / 100_000) % 10)
        return result
    }

    // Returns whether the capture has a duration, rather than one picture.
    mtd const isTimed()->bool => .media != .Picture

    // Returns the path of the frame file that belongs to the capture file `file`.
    func mediaPathOf(file: string, media: CaptureMedia = .Animation)->String
    {
        var name = String.from(Path.fileNameWithoutExtension(file) orelse "")
        name += media == .Video ? CaptureVideoExtension : CaptureMediaExtension
        return Path.combine(Path.directoryName(file), name)
    }

    // Copies the capture file `source` to `target`, with its frame file when it has one. Nothing
    // is left at `target` when a copy fails.
    func duplicateFiles(target, source: string) fail
    {
        try File.duplicate(target, source)
        defer #fail
        {
            for kind in [CaptureMedia.Animation, CaptureMedia.Video]
            {
                let path = mediaPathOf(target, kind)
                if File.exists(path) do
                    discard catch File.delete(path)
            }
            discard catch File.delete(target)
        }

        for kind in [CaptureMedia.Animation, CaptureMedia.Video]
        {
            let media = mediaPathOf(source, kind)
            if File.exists(media) do
                try File.duplicate(mediaPathOf(target, kind), media)
        }
    }

    // Deletes the capture file `file` and its frame file.
    func deleteFiles(file: string) fail
    {
        for kind in [CaptureMedia.Animation, CaptureMedia.Video]
        {
            let media = mediaPathOf(file, kind)
            if File.exists(media) do
                try File.delete(media)
        }
        try File.delete(file)
    }

    // Makes a new animation capture in the library from the animated picture at `path`, its frames
    // written to a frame file; null when the picture holds fewer than two frames of animation.
    func importAnimation(path: string)->*Capture? fail
    {
        let bytes  = try File.readAllBytes(path)
        var reader = try ImageReader.decode(path, bytes.toSlice())
        let info   = &reader.info

        var animated = 0
        for frame in info.frames where frame.kind == .Animation do
            animated += 1
        if animated < 2 or info.canvasWidth <= 0 or info.canvasHeight <= 0 do
            return null

        // The frames are the composited canvas of each step, held for their encoded duration; an
        // unspecified one shows for a tenth of a second, as viewers do.
        let file   = Library.newFileName()
        let media  = mediaPathOf(file)
        var writer = try Frames.Writer.create(media, info.canvasWidth, info.canvasHeight, .RGBA8)
        defer #fail discard catch File.delete(media)

        var time = 0'u64
        for index in info.frames.count where info.frames[index].kind == .Animation
        {
            var picture = try reader.read(cast(u32, index))
            if picture.pixelFormat != .RGBA8 do
                picture.convertTo(.RGBA8)
            try writer.add(picture, time)

            let seconds = info.frames[index].durationSeconds
            time += seconds > 0 ? cast(u64, seconds * 1_000_000) : 100_000
        }

        try writer.close(time)

        let result = Memory.new'Capture()
        defer #fail Memory.delete(result)
        result.file       = file
        result.sourceKind = .ImageFile
        result.capturedAt = Time.DateTime.now()
        try result.adoptRecording()
        return result
    }

    // Makes the capture an animation over the frame file recorded beside its file, and shows the
    // first frame.
    mtd adoptRecording() fail
    {
        .closeMedia()

        let path   = mediaPathOf(.file)
        var frames = try TimedReader.open(path, .Animation)

        .media               = .Animation
        .timeline.frameCount = frames.frameCount()
        .timeline.duration   = frames.endTime
        .timeline.mediaSize  = (try File.info(path)).size
        .width, .widthOrg    = frames.width
        .height, .heightOrg  = frames.height
        .playhead            = 0
        .mediaMissing        = false

        .takeFrames(&frames)
        try .showFrame(0)
    }

    // Makes a newly completed MP4 the editable timed media of this capture.
    mtd adoptVideo() fail
    {
        .closeMedia()
        let path = mediaPathOf(.file, .Video)
        var frames = try TimedReader.open(path, .Video)
        if not frames.frameCount() do
            fail Errors.InvalidFormatError{}
        .media               = .Video
        .timeline.frameCount = frames.frameCount()
        .timeline.duration   = frames.endTime
        .timeline.mediaSize  = (try File.info(path)).size
        .width, .widthOrg    = frames.width
        .height, .heightOrg  = frames.height
        .playhead            = 0
        .mediaMissing        = false
        .takeFrames(&frames)
        try .showFrame(0)
    }

    // Opens the frame file of a timed capture and shows the frame at the playhead. A file that is
    // missing, unreadable or was replaced since the recording marks the media missing.
    mtd openMedia()
    {
        .closeMedia()
        .mediaMissing = true

        let path = mediaPathOf(.file, .media)
        let info = catch File.info(path) { return; }
        if info.size != .timeline.mediaSize do
            return

        var frames = catch TimedReader.open(path, .media) { return; }
        if frames.frameCount() != .timeline.frameCount or frames.frameCount() == 0 do
            return

        .takeFrames(&frames)
        catch .showFrame(Math.min(.playhead, .timeline.frameCount - 1)) do
            return
        .mediaMissing = false
    }

    // Returns the time of the frame at the playhead, in microseconds; zero for a picture.
    mtd const playheadTime()->u64
    {
        if not .isTimed() do
            return 0
        let frames = .frames
        if not frames do
            return 0
        return frames.timeOf(.playhead)
    }

    // Returns whether `itf` shows at the playhead: always on a picture, inside its time span on a
    // timed capture.
    mtd const isFormShown(itf: IForm)->bool
    {
        if not .isTimed() do
            return true
        let form: *BaseForm = itf
        let time = .playheadTime()
        return time >= form.timeStart and (form.timeEnd == 0 or time < form.timeEnd)
    }

    // Returns where the kept part of a timed capture starts, in microseconds.
    mtd const trimStart()->u64 => .timeline.inPoint

    // Returns where the kept part of a timed capture ends, in microseconds.
    mtd const trimEnd()->u64 => .timeline.outPoint ? .timeline.outPoint : .timeline.duration

    // Returns the length of the kept part, in microseconds; zero for a picture.
    mtd const keptDuration()->u64 => .isTimed() ? .trimEnd() - .trimStart() : 0

    // Returns whether the capture keeps less than its whole recording.
    mtd const isTrimmed()->bool => .timeline.inPoint != 0 or .timeline.outPoint != 0

    // Keeps a non-empty part of the recording from `inPoint` until `outPoint`, in microseconds,
    // as one undoable edit. An `outPoint` of zero, or at the end, keeps it to its end.
    mtd setTrim(inPoint, outPoint: u64)
    {
        if not .isTimed() do
            return

        let duration = .timeline.duration
        if duration == 0 do
            return

        let finish = outPoint == 0 or outPoint >= duration ? duration : Math.max(outPoint, 1)
        let start  = Math.min(inPoint, finish - 1)
        let trimmedFinish = finish >= duration ? 0 : finish
        if start == .timeline.inPoint and trimmedFinish == .timeline.outPoint do
            return

        with let undo = .newUndo(.SetTrim)
        {
            .trimIn  = start
            .trimOut = trimmedFinish
        }

        .pushUndo(undo)
        .hasChanged()
    }

    // Moves the playhead by `step` frames, within the capture.
    mtd stepFrame(step: s64) fail
    {
        let frames = .frames
        if not frames do
            return
        let last   = cast(s64, frames.frameCount()) - 1
        let target = Math.clamp(cast(s64, .playhead) + step, 0, last)
        try .showFrame(cast(u64, target))
    }

    // Makes the selected forms start, or end, at the playhead, as one undoable edit. A boundary
    // that would cross the other one stops one microsecond before or after it.
    mtd setSelectionSpan(start: bool)
    {
        .setSelectionSpanAt(start, .playheadTime())
    }

    // Places the selected forms' start or end at `time` as one undoable edit. Zero as an end
    // means that the forms continue to the end of the recording.
    mtd setSelectionSpanAt(start: bool, time: u64)
    {
        if not .isTimed() or .selection.isEmpty() do
            return
        with let undo = .newUndo(.SetTimeSpan)
        {
            .spanTime  = Math.min(time, me.timeline.duration)
            .spanStart = start
        }

        .pushUndo(undo)
        .hasChanged()
    }

    // Shows the selected forms for the whole capture again, as one undoable edit.
    mtd clearSelectionSpan()
    {
        if not .isTimed() or .selection.isEmpty() do
            return
        with let undo = .newUndo(.SetTimeSpan)
        {
            .spanClear = true
        }

        .pushUndo(undo)
        .hasChanged()
    }

    // Returns whether this capture is the one stored in `file`.
    mtd const isStoredIn(file: string)->bool => not .file.isEmpty() and Path.equals(.file, file)

    // Closes the frame file of a timed capture.
    mtd closeMedia()
    {
        if not .frames do
            return
        Memory.delete(.frames)
        .frames = null
    }

    // Shows frame `frame` on the canvas.
    mtd showFrame(frame: u64) fail
    {
        let picture = try .frames!.read(frame)
        .backImg      = picture[]
        .playhead     = frame
        .dirtyBackImg = true
        .editView?.invalidate()
    }

    // Writes the animation, with its annotations, as an animated GIF at `path`.
    //
    // Each frame is shown on the canvas in turn to be rendered; the frame at the playhead is
    // shown again afterwards.
    mtd exportAnimation(path: string) fail
    {
        let frames   = unwrap .frames
        let playhead = .playhead
        defer catch .showFrame(playhead)

        var writer = try Gif.AnimationWriter.create(path, .width, .height)
        defer #fail discard catch File.delete(path)

        // Only the kept part is written: each frame is held for the time it shows inside it.
        let start  = .trimStart()
        let finish = .trimEnd()
        let count  = frames.frameCount()
        for frame in frames.frameAt(start) until count
        {
            let shown = Math.max(frames.timeOf(frame), start)
            if shown >= finish do
                break

            let next = frame + 1 < count ? frames.timeOf(frame + 1) : frames.endTime
            try .showFrame(frame)
            try writer.addFrame(.toImage(), Math.min(next, finish) - shown)
        }

        try writer.end()
    }

    // Exports the animation to a GIF named after the capture in the temporary folder, and puts
    // that file on the clipboard.
    mtd copyAnimation() fail
    {
        let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "Swag Capture")
        if not Directory.exists(folder) do
            try Directory.create(folder)

        var name = String.from(Path.fileNameWithoutExtension(.displayName()) orelse "animation")
        name += ".gif"
        let path = Path.combine(folder, name)
        try .exportAnimation(path)

        var files: Array'String
        files.add(path)
        Clipboard.setFiles(files.toSlice())
    }

    // Keeps `frames` open as the frames of the capture.
    private mtd takeFrames(frames: *TimedReader)
    {
        let owned = Memory.new'TimedReader()
        owned[] = #move frames[]
        .frames = owned
    }
}

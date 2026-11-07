impl Capture
{
    // Returns whether the capture has a duration, rather than one picture.
    mtd const isTimed()->bool => .media != .Picture

    // Returns the path of the frame file that belongs to the capture file `file`.
    func mediaPathOf(file: string)->String
    {
        var name = String.from(Path.fileNameWithoutExtension(file) orelse "")
        name += CaptureMediaExtension
        return Path.combine(Path.directoryName(file), name)
    }

    // Copies the capture file `source` to `target`, with its frame file when it has one. Nothing
    // is left at `target` when a copy fails.
    func duplicateFiles(target, source: string) fail
    {
        try File.duplicate(target, source)
        defer #fail discard catch File.delete(target)

        let media = mediaPathOf(source)
        if File.exists(media) do
            try File.duplicate(mediaPathOf(target), media)
    }

    // Deletes the capture file `file` and its frame file.
    func deleteFiles(file: string) fail
    {
        let media = mediaPathOf(file)
        if File.exists(media) do
            try File.delete(media)
        try File.delete(file)
    }

    // Makes the capture an animation over the frame file recorded beside its file, and shows the
    // first frame.
    mtd adoptRecording() fail
    {
        .closeMedia()

        let path   = mediaPathOf(.file)
        var frames = try Frames.Reader.open(path)

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

    // Opens the frame file of a timed capture and shows the frame at the playhead. A file that is
    // missing, unreadable or was replaced since the recording marks the media missing.
    mtd openMedia()
    {
        .closeMedia()
        .mediaMissing = true

        let path = mediaPathOf(.file)
        let info = catch File.info(path) { return; }
        if info.size != .timeline.mediaSize do
            return

        var frames = catch Frames.Reader.open(path) { return; }
        if frames.frameCount() != .timeline.frameCount or frames.frameCount() == 0 do
            return

        .takeFrames(&frames)
        catch .showFrame(Math.min(.playhead, .timeline.frameCount - 1)) do
            return
        .mediaMissing = false
    }

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

        let count = frames.frameCount()
        for frame in count
        {
            try .showFrame(frame)
            let end = frame + 1 < count ? frames.timeOf(frame + 1) : frames.endTime
            try writer.addFrame(.toImage(), end - frames.timeOf(frame))
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
    private mtd takeFrames(frames: *Frames.Reader)
    {
        let owned = Memory.new'Frames.Reader()
        owned[] = #move frames[]
        .frames = owned
    }
}

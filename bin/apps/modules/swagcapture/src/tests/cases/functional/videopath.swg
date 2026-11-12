#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Video

// Video and project stems differ so a player cannot mistake the SCC document for captions.
#test
{
    let document = testTempCapturePath()
    let video    = Capture.mediaPathOf(document, .Video)
    Swag.require(Path.fileNameWithoutExtension(video) != Path.fileNameWithoutExtension(document))
    Swag.require(Utf8.startsWith(Path.fileName(video), "video-"))
    Swag.require(Path.lowercaseExtension(video) == ".mp4")
}

// An interrupted fragmented MP4 is turned back into a capture document on the next scan.
#test
{
    let folder = Gui.Testing.tempFilePath("capture-recovery-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let document = Path.combine(folder, "interrupted.scc")
    let media = Capture.mediaPathOf(document, .Video)
    let source = Gui.Testing.tempFilePath("capture-source-", ".mp4")
    defer discard catch File.delete(source)

    var picture = Image.create(32, 16, .BGRA8)
    picture.fill(Argb.White)
    var writer = expect Mp4.SoftwareRecording.createVideoOnly(source, 32, 16, 1_000_000)
    for frame in 3'u64 do
        expect writer.addFrame(&picture, FrameSlot{frame, frame * 100_000, 100_000, 0})
    expect writer.flush()
    var input = expect ByteSource.openFile(source, .ReadWrite)
    var prefix: Array'u8
    prefix.resize(input.size())
    expect input.readExact(prefix.toSlice())
    discard expect File.writeAllBytes(media, prefix.toSlice())
    expect writer.end()

    let invalid = Path.combine(folder, "video-invalid.mp4")
    discard expect File.writeAllText(invalid, "not a video")
    let recovered = expect Library.recoverOrphanVideos(folder)
    Swag.require(recovered.count == 1 and recovered[0] == document)
    let second = expect Library.recoverOrphanVideos(folder)
    Swag.require(second.isEmpty())
    for index in 5'u64
    {
        let nextDocument = Path.combine(folder, Format.toString("extra-%.scc", index))
        expect File.duplicate(Capture.mediaPathOf(nextDocument, .Video), media)
    }
    let batch = expect Library.recoverOrphanVideos(folder)
    Swag.require(batch.count == VideoRecoveryBatchSize)
    let last = expect Library.recoverOrphanVideos(folder)
    Swag.require(last.count == 1)
    let capture = expect Capture.load(document)
    defer Memory.delete(capture)
    Swag.require(capture.media == .Video and not capture.mediaMissing)
    Swag.require(capture.timeline.frameCount == 3)
    Swag.require(File.exists(media) and not File.exists(Path.combine(folder, "invalid.scc")))
}

// An existing same-stem recording remains readable; copies adopt the new naming convention.
#test
{
    let document = testTempCapturePath()
    let legacy   = Path.combine(Path.directoryName(document),
                                Format.toString("%.mp4", Path.fileNameWithoutExtension(document) orelse ""))
    let target = testTempCapturePath()
    discard expect File.writeAllText(document, "capture document")
    discard expect File.writeAllText(legacy, "legacy video")
    defer discard catch Capture.deleteFiles(document)
    defer discard catch Capture.deleteFiles(target)
    Swag.require(Path.equals(Capture.mediaPathOf(document, .Video), legacy))
    expect Capture.duplicateFiles(target, document)
    let copied = Capture.mediaPathOf(target, .Video)
    Swag.require(Utf8.startsWith(Path.fileName(copied), "video-"))
    Swag.require(expect File.readAllText(copied) == "legacy video")
    expect Capture.deleteFiles(document)
    Swag.require(not File.exists(legacy) and not File.exists(document))
}

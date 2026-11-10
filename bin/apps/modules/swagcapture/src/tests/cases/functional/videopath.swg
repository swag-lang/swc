#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Video and project stems differ so a player cannot mistake the SCC document for captions.
#test
{
    let document = testTempCapturePath()
    let video    = Capture.mediaPathOf(document, .Video)
    Swag.require(Path.fileNameWithoutExtension(video) != Path.fileNameWithoutExtension(document))
    Swag.require(Utf8.startsWith(Path.fileName(video), "video-"))
    Swag.require(Path.lowercaseExtension(video) == ".mp4")
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

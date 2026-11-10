#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Records three frames beside a new capture file and makes the capture an animation over them.
func testRecordedCapture()->*Capture
{
    var pictures: [3] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)
    pictures[2] = testFramePicture(70, 16)

    with let result = Memory.new'Capture()
    {
        .file = testTempCapturePath()
        expect testWriteFrames(Capture.mediaPathOf(.file), pictures, 100_000)
        expect .adoptRecording()
    }

    return result
}

func testProfileVersion(file: string)->u32
{
    var reader: Scc.Reader
    expect reader.initialize(file)
    return reader.manifest().profileVersion
}

// The secondary timeline menu collects playback, recording-range, and selected-form commands.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    main.editWnd.editView.setCapture(capture)

    let shape = testAddArrow(capture, 4, 4, 20, 10)
    shape.timeStart = 50_000
    shape.timeEnd   = 250_000
    capture.selection.add(0)
    capture.setTrim(50_000, 250_000)
    expect capture.showFrame(1)
    main.updateState()

    let bar = unwrap main.timeline
    var inspected: bool
    host.app.sigFrame += func|host = &host, capture = capture, shape = shape, inspected = &inspected|(_)
    {
        if inspected[] do
            return

        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 11)
        Swag.require(menu.items[0]!.id == ActionTimeline.Play)
        Swag.require(menu.items[1]!.id == ActionTimeline.PrevFrame)
        Swag.require(menu.items[2]!.id == ActionTimeline.NextFrame)
        Swag.require(menu.items[3]!.separator)
        Swag.require(menu.items[4]!.id == ActionTimeline.TrimStart and not menu.items[4]!.disabled)
        Swag.require(menu.items[5]!.id == ActionTimeline.TrimEnd and not menu.items[5]!.disabled)
        Swag.require(menu.items[6]!.id == ActionTimeline.KeepAll and not menu.items[6]!.disabled)
        Swag.require(menu.items[7]!.separator)
        Swag.require(menu.items[8]!.id == ActionTimeline.ShowFrom and not menu.items[8]!.disabled)
        Swag.require(menu.items[9]!.id == ActionTimeline.ShowUntil and not menu.items[9]!.disabled)
        Swag.require(menu.items[10]!.id == ActionTimeline.ShowAlways and not menu.items[10]!.disabled)
        let iconItems = [0, 1, 2, 4, 5, 6, 8, 9, 10]
        for left, index in iconItems
        {
            Swag.require(menu.items[left]!.icon.isValid())
            for right in index + 1 until iconItems.count do
                Swag.require(menu.items[left]!.icon != menu.items[iconItems[right]]!.icon)
        }

        expect capture.showFrame(0)
        menu.updateState()
        Swag.require(menu.items[1]!.disabled)
        Swag.require(not menu.items[2]!.disabled)

        expect capture.showFrame(2)
        menu.updateState()
        Swag.require(not menu.items[1]!.disabled)
        Swag.require(menu.items[2]!.disabled)

        capture.setTrim(50_000, 100_000)
        menu.updateState()
        Swag.require(menu.items[4]!.disabled)
        Swag.require(not menu.items[5]!.disabled)

        shape.timeEnd = 150_000
        menu.updateState()
        Swag.require(menu.items[8]!.disabled)
        Swag.require(not menu.items[9]!.disabled)

        shape.timeStart = 250_000
        shape.timeEnd   = 0
        menu.updateState()
        Swag.require(not menu.items[8]!.disabled)
        Swag.require(menu.items[9]!.disabled)

        shape.timeStart = 50_000
        shape.timeEnd   = 250_000
        capture.setTrim(50_000, 250_000)
        expect capture.showFrame(1)
        menu.updateState()
        Swag.require(not menu.items[4]!.disabled and not menu.items[5]!.disabled)
        Swag.require(not menu.items[8]!.disabled and not menu.items[9]!.disabled)
        inspected[] = true
        Swag.require(host.clickPopupMenuItem(ActionTimeline.TrimStart))
    }

    host.click(bar.localToSurface(bar.trackRect().center()), button: .Right)
    host.app.sigFrame.clear()
    Swag.require(inspected)
    host.pump()
    Swag.require(capture.trimStart() == capture.playheadTime())

    capture.setTrim(50_000, 100_000)
    expect capture.showFrame(0)
    main.sendCommandEvent(ActionTimeline.TrimEnd)
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 100_000)

    capture.setTrim(50_000, 100_000)
    expect capture.showFrame(2)
    main.sendCommandEvent(ActionTimeline.TrimStart)
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 100_000)

    capture.setSelectionSpanAt(true, 300_000)
    Swag.require(shape.timeStart == 249_999 and shape.timeEnd == 250_000)
    capture.undo()
    capture.setSelectionSpanAt(false, 40_000)
    Swag.require(shape.timeStart == 50_000 and shape.timeEnd == 50_001)
    capture.undo()
}

// A long recording can zoom around a chosen time, pan, and seek inside the visible range without
// decoding a frame elsewhere in the recording.
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()

    let capture = Memory.new'Capture()
    capture.file = testTempCapturePath()
    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)

    var pictures: [3] Pixel.Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)
    pictures[2] = testFramePicture(70, 16)
    expect testWriteFrames(Capture.mediaPathOf(file), pictures, 7_200_000_000)
    expect capture.adoptRecording()
    fixture.editView.setCapture(capture)

    let bar = TimelineBar.create(fixture.main, &fixture.gui.root)
    bar.resize(800, TimelineHeight)
    let track = bar.trackRect()
    let center = track.horzCenter()
    Swag.require(capture.timeline.duration == 21_600_000_000)
    Swag.require(bar.timeAt(center) >= 10_400_000_000)

    bar.zoomAt(center, 4)
    Swag.require(bar.visibleDuration() == 5_400_000_000)
    Swag.require(bar.viewStart > 0)
    Swag.require(Math.abs(cast(s64, bar.timeAt(center)) - 10_800_000_000) < 10_000)

    bar.pan(0.5)
    Swag.require(bar.viewStart > 8_000_000_000)
    bar.seek(track.right())
    Swag.require(capture.playhead == 2)
}

// A selected form's start and end can be dragged on the timeline as separate undoable edits.
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()

    let capture = testRecordedCapture()
    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    fixture.editView.setCapture(capture)

    let shape = testAddShape(capture, 4, 4, 20, 10)
    shape.timeStart = 100_000
    shape.timeEnd   = 200_000
    capture.selection.add(0)

    let bar = TimelineBar.create(fixture.main, &fixture.gui.root)
    bar.resize(800, TimelineHeight)
    let y = bar.trackRect().vertCenter() + 8
    Swag.require(bar.edgeAt(bar.trackX(100_000), y) == .FormStart)
    Swag.require(bar.edgeAt(bar.trackX(200_000), y) == .FormEnd)

    bar.dragEdge = .FormStart
    bar.dragFromStart = shape.timeStart
    bar.dragFromEnd   = shape.timeEnd
    bar.drag(bar.trackX(150_000))
    bar.endEdgeDrag()
    Swag.require(shape.timeStart == 150_000 and shape.timeEnd == 200_000)
    capture.undo()
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 200_000)

    bar.dragEdge = .FormEnd
    bar.dragFromStart = shape.timeStart
    bar.dragFromEnd   = shape.timeEnd
    bar.drag(bar.trackX(300_000))
    bar.endEdgeDrag()
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 0)
    capture.undo()
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 200_000)

    bar.dragEdge      = .FormStart
    bar.dragFromStart = shape.timeStart
    bar.dragFromEnd   = shape.timeEnd
    bar.drag(bar.trackX(250_000))
    Swag.require(shape.timeStart == 199_999 and shape.timeEnd == 200_000)
    bar.endEdgeDrag()
    capture.undo()

    bar.dragEdge      = .FormEnd
    bar.dragFromStart = shape.timeStart
    bar.dragFromEnd   = shape.timeEnd
    bar.drag(bar.trackX(50_000))
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 100_001)
    bar.endEdgeDrag()
    capture.undo()
}

// A timed capture saves its forms and timeline without touching its frame file, loads back with
// the frame at its playhead on the canvas, and reads as an animation in the library without
// opening its frames.
#test
{
    let first = testFramePicture(10, 0)
    let last  = testFramePicture(70, 16)

    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    let media   = Capture.mediaPathOf(file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)

    Swag.require(capture.isTimed())
    Swag.require(capture.width == 64 and capture.height == 48)
    Swag.require(capture.timeline.frameCount == 3 and capture.timeline.duration == 300_000)
    Swag.require(testSamePixels(&capture.backImg, &first))

    let mediaBefore = expect File.readAllBytes(media)
    discard testAddShape(capture, 4, 4, 20, 10)
    capture.changed = true
    expect capture.save()
    expect capture.save()

    let mediaAfter = expect File.readAllBytes(media)
    Swag.require(mediaAfter.count == mediaBefore.count)
    Swag.require(Memory.compare(mediaAfter.storage(), mediaBefore.storage(), mediaAfter.count) == 0)
    Swag.require(testProfileVersion(file) == CaptureProfileVersion)

    let loaded = expect Capture.load(file)
    defer Memory.delete(loaded)
    Swag.require(loaded.media == .Animation and not loaded.mediaMissing)
    Swag.require(loaded.timeline.frameCount == 3 and loaded.timeline.duration == 300_000)
    Swag.require(loaded.forms.count == 1)
    Swag.require(testSamePixels(&loaded.backImg, &first))

    expect loaded.showFrame(2)
    Swag.require(loaded.playhead == 2)
    Swag.require(testSamePixels(&loaded.backImg, &last))

    let preview = expect Capture.load(file, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.media == .Animation and preview.timeline.duration == 300_000)
    Swag.require(preview.frames == null)
}

// A frame file replaced after the recording is reported instead of being shown.
#test
{
    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)

    capture.changed = true
    expect capture.save()
    capture.closeMedia()

    var bytes = expect File.readAllBytes(Capture.mediaPathOf(file))
    bytes.add(0)
    discard expect File.writeAllBytes(Capture.mediaPathOf(file), bytes.toSlice())

    let loaded = expect Capture.load(file)
    defer Memory.delete(loaded)
    Swag.require(loaded.mediaMissing)
    Swag.require(loaded.frames == null)
}

// A picture keeps the profile every earlier version reads.
#test
{
    with let capture = Memory.new'Capture()
    {
        .file    = testTempCapturePath()
        .width   = 32
        .height  = 32
        .backImg = Image.create(32, 32, .BGRA8)
        .changed = true
    }

    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)

    expect capture.save()
    Swag.require(testProfileVersion(file) == CapturePictureProfileVersion)
}

// Moving a timed capture through the library carries its frame file along.
#test
{
    let capture = testRecordedCapture()
    defer Memory.delete(capture)
    let file = String.from(capture.file)
    capture.changed = true
    expect capture.save()
    capture.closeMedia()

    let folder = Gui.Testing.tempFilePath("library-", "")
    expect Directory.create(folder)
    defer catch Directory.delete(folder, recurse: true)

    let moved = Library.moveFile(folder, file)
    Swag.require(not moved.isEmpty())
    Swag.require(not File.exists(file) and not File.exists(Capture.mediaPathOf(file)))
    Swag.require(File.exists(Capture.mediaPathOf(moved)))

    let loaded = expect Capture.load(moved)
    defer Memory.delete(loaded)
    Swag.require(not loaded.mediaMissing)
}

// An animation exports as an animated GIF with its frames, its timing and its annotations, and
// leaves the frame at the playhead on the canvas.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    f.editView.setCapture(capture)
    f.capture = capture
    expect capture.showFrame(1)

    let path = Gui.Testing.tempFilePath("animation-", ".gif")
    defer catch File.delete(path)
    expect capture.exportAnimation(path)
    Swag.require(capture.playhead == 1)

    let bytes  = expect File.readAllBytes(path)
    var reader = expect ImageReader.decode("animation.gif", bytes.toSlice())
    Swag.require(reader.info.frames.count == 3)
    Swag.require(reader.info.canvasWidth == 64 and reader.info.canvasHeight == 48)
    for frame in reader.info.frames do
        Swag.require(Math.abs(frame.durationSeconds - 0.1) < 0.001)
}

// Deleting the animation being edited moves it to the trash with its frame file, although the
// editor holds that file open.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    var pictures: [2] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)

    let capture = Memory.new'Capture()
    capture.file = Library.newFileName()
    expect testWriteFrames(Capture.mediaPathOf(capture.file), pictures, 100_000)
    expect capture.adoptRecording()
    capture.changed = true
    expect capture.save()
    let file = String.from(capture.file)
    f.editView.setCapture(capture)
    f.capture = capture
    g_Library.addFile(file)

    g_Library.removeFile(file)
    Swag.require(not File.exists(file))
    Swag.require(not File.exists(Capture.mediaPathOf(file)))

    let trashed = Path.combine(Library.getTrashFolder(), Path.fileName(file) orelse "")
    Swag.require(File.exists(trashed) and File.exists(Capture.mediaPathOf(trashed)))
    expect Capture.deleteFiles(trashed)
}

// An animated GIF opens as an animation, with its frames and their timing; a still picture does
// not.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let gif = Gui.Testing.tempFilePath("animated-", ".gif")
    defer catch File.delete(gif)
    var writer = expect Gif.AnimationWriter.create(gif, 64, 48)
    expect writer.addFrame(testFramePicture(10, 0), 200_000)
    expect writer.addFrame(testFramePicture(40, 8), 300_000)
    expect writer.end()

    let capture = expect Capture.importAnimation(gif)
    Swag.require(capture != null)
    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)

    Swag.require(capture.isTimed() and capture.sourceKind == .ImageFile)
    Swag.require(capture.width == 64 and capture.height == 48)
    Swag.require(capture.timeline.frameCount == 2 and capture.timeline.duration == 500_000)

    let still = Gui.Testing.tempFilePath("still-", ".png")
    defer catch File.delete(still)
    expect testFramePicture(10, 0).save(still)
    Swag.require(expect Capture.importAnimation(still) == null)
}

// A form shown from the playhead on is hidden before it, cannot be picked there, and leaves the
// exported frames before its start; undo shows it for the whole animation again.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    f.editView.setCapture(capture)
    f.capture = capture

    let shape = testAddShape(capture, 4, 4, 20, 10)
    capture.selection.clear()
    capture.selection.add(0)

    expect capture.showFrame(1)
    capture.setSelectionSpan(start: true)
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 0)
    Swag.require(capture.isFormShown(shape))

    expect capture.showFrame(0)
    Swag.require(not capture.isFormShown(shape))
    Swag.require(capture.hitTests({10, 8}, false).isEmpty())

    expect capture.showFrame(2)
    capture.setSelectionSpan(start: false)
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 200_000)
    Swag.require(not capture.isFormShown(shape))

    capture.setSelectionSpanAt(start: false, time: 300_000)
    Swag.require(shape.timeStart == 100_000 and shape.timeEnd == 0)

    capture.undo()
    capture.undo()
    capture.undo()
    Swag.require(shape.timeStart == 0 and shape.timeEnd == 0)
    Swag.require(capture.isFormShown(shape))
}

// Trimming keeps a part of the recording without cutting its frames: the export holds only that
// part, each frame for the time it shows inside it, and undo keeps the whole recording again.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let capture = testRecordedCapture()
    let file    = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    f.editView.setCapture(capture)
    f.capture = capture
    let bar = TimelineBar.create(f.main, &f.gui.root)
    bar.resize(800, TimelineHeight)

    capture.setTrim(50_000, 250_000)
    Swag.require(capture.isTrimmed())
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 250_000)
    Swag.require(capture.timeline.frameCount == 3)

    let path = Gui.Testing.tempFilePath("trimmed-", ".gif")
    defer catch File.delete(path)
    expect capture.exportAnimation(path)

    let bytes  = expect File.readAllBytes(path)
    var reader = expect ImageReader.decode("trimmed.gif", bytes.toSlice())
    Swag.require(reader.info.frames.count == 3)
    Swag.require(Math.abs(reader.info.frames[0].durationSeconds - 0.05) < 0.001)
    Swag.require(Math.abs(reader.info.frames[1].durationSeconds - 0.1) < 0.001)
    Swag.require(Math.abs(reader.info.frames[2].durationSeconds - 0.05) < 0.001)

    // An end set at the last instant keeps the recording to its end.
    capture.setTrim(50_000, 300_000)
    Swag.require(capture.timeline.outPoint == 0 and capture.trimEnd() == 300_000)

    capture.setTrim(300_000, 100_000)
    Swag.require(capture.trimStart() == 99_999 and capture.trimEnd() == 100_000)

    capture.setTrim(50_000, 100_000)
    bar.dragEdge    = .Start
    bar.dragFromIn  = 50_000
    bar.dragFromOut = 100_000
    bar.drag(bar.trackX(250_000))
    Swag.require(capture.trimStart() == 99_999 and capture.trimEnd() == 100_000)
    bar.endEdgeDrag()
    capture.undo()

    bar.dragEdge    = .End
    bar.dragFromIn  = 50_000
    bar.dragFromOut = 100_000
    bar.drag(bar.trackX(0))
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 50_001)
    bar.endEdgeDrag()
    capture.undo()
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 100_000)

    capture.undo()
    Swag.require(capture.trimStart() == 99_999 and capture.trimEnd() == 100_000)
    capture.undo()
    Swag.require(capture.trimStart() == 50_000 and capture.trimEnd() == 300_000)
    capture.undo()
    capture.undo()
    Swag.require(not capture.isTrimmed())
}

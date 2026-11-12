#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Export a library preview by loading the full document on a worker before rendering it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let source = journey.newCapture(41, 29)
    let main = journey.main
    journey.openLibrary(1)
    main.libWnd.view.setFocusItem(0)

    var exported = Path.combine(journey.root, "exported.png")
    var previous = Image.create(3, 2, .BGRA8)
    previous.fill(Argb.White)
    expect previous.save(exported)
    main.doSaveAsImage(exported)
    Swag.require(main.exportJob != null)
    journey.waitFor("library image exported", func|main, &exported|()->bool =>
                    main.exportJob == null and main.imageWriteJob == null and File.exists(exported))

    let image = expect Image.load(exported)
    Swag.require(image.width == 41 and image.height == 29)
    var sourceMetadata: bool
    for md in image.metadata where md.isTag(CaptureFileMetadataTag) do
        sourceMetadata = sourceMetadata or Path.equals(cast(string, md.toSlice()), source)
    Swag.require(sourceMetadata)

    var linked = Path.combine(journey.root, "linked.png")
    main.doSaveAsImage(linked, linked: true)
    journey.waitFor("library image linked", func|main, &linked|()->bool =>
                    main.exportJob == null and File.exists(linked))
    let capture = expect Capture.load(source)
    defer Memory.delete(capture)
    Swag.require(capture.linkedImage == linked and capture.linkedUpToDate)
}

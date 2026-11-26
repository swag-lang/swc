#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Audio, Viewers

private struct Fixture
{
    name:    string
    viewer:  string
    aliasOf: string = ""
}

// A collection wraps a real face and still exposes its character map to the font reader.
#test
{
    let bytes = expect File.readAllBytes(scopeTestDataPath("viewer.arabic.ttc"))
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    Swag.require(face.hasChar('ع'))
    let bold = expect Face.loadAt(bytes.toSlice(), 1)
    defer bold.destroy()
    Swag.require(bold.hasChar('ع'))
}

// Every canonical format fixture and named variant selects its intended reading surface.
#test
{
    const Cases: [219] Fixture = [
        Fixture{"viewer.txt", "text"},
        Fixture{"viewer.field-notes.txt", "text"},
        Fixture{"viewer.cpp", "code"},
        Fixture{"viewer.field-station.cpp", "code"},
        Fixture{"viewer.md", "markdown"},
        Fixture{"viewer.markdown", "markdown"},
        Fixture{"viewer.html", "html"},
        Fixture{"viewer.field-guide.html", "html"},
        Fixture{"viewer.htm", "html"},
        Fixture{"viewer.xhtml", "html"},
        Fixture{"viewer.pdf", "pdf"},
        Fixture{"viewer.epub", "epub"},
        Fixture{"viewer.docx", "docx"},
        Fixture{"viewer.formatted.docx", "docx"},
        Fixture{"viewer.image.docx", "docx"},
        Fixture{"viewer.headers.docx", "docx"},
        Fixture{"viewer.bad-header.docx", "docx"},
        Fixture{"viewer.numbering.docx", "docx"},
        Fixture{"viewer.numbering-overrides.docx", "docx"},
        Fixture{"viewer.numbering-missing.docx", "docx"},
        Fixture{"viewer.footnotes.docx", "docx"},
        Fixture{"viewer.bad-footnotes.docx", "docx"},
        Fixture{"viewer.endnotes.docx", "docx"},
        Fixture{"viewer.external-links.docx", "docx"},
        Fixture{"viewer.sections.docx", "docx"},
        Fixture{"viewer.table-span.docx", "docx"},
        Fixture{"viewer.table-merge.docx", "docx"},
        Fixture{"viewer.table-merge-span.docx", "docx"},
        Fixture{"viewer.bad-table-merge.docx", "docx"},
        Fixture{"viewer.nested-table.docx", "docx"},
        Fixture{"viewer.links.docx", "docx"},
        Fixture{"viewer.comments.docx", "docx"},
        Fixture{"viewer.bad-comments.docx", "docx"},
        Fixture{"viewer.poi-pictures.docx", "docx"},
        Fixture{"viewer.christmas-carol.docx", "docx"},
        Fixture{"viewer.rtf", "rtf"},
        Fixture{"viewer.large-control.rtf", "rtf"},
        Fixture{"viewer.styles.rtf", "rtf"},
        Fixture{"viewer.unicode.rtf", "rtf"},
        Fixture{"viewer.table.rtf", "rtf"},
        Fixture{"viewer.destinations.rtf", "rtf"},
        Fixture{"viewer.damaged.rtf", "rtf"},
        Fixture{"viewer.libreoffice.rtf", "rtf"},
        Fixture{"viewer.christmas-carol.rtf", "rtf"},
        Fixture{"viewer.xlsx", "xlsx"},
        Fixture{"viewer.navigation.xlsx", "xlsx"},
        Fixture{"viewer.geometry.xlsx", "xlsx"},
        Fixture{"viewer.styles.xlsx", "xlsx"},
        Fixture{"viewer.cbz", "comic"},
        Fixture{"viewer.peppercarrot.ep01.cbz", "comic"},
        Fixture{"viewer.peppercarrot.ep36.cbz", "comic"},
        Fixture{"viewer.zip", "archive"},
        Fixture{"viewer.zip64.zip", "archive"},
        Fixture{"viewer.zip-descriptor.zip", "archive"},
        Fixture{"viewer.zip-unicode-duplicates.zip", "archive"},
        Fixture{"viewer.zipcrypto-encrypted.zip", "archive"},
        Fixture{"viewer.zip-damaged-directory.zip", "archive"},
        Fixture{"viewer.zip-preview-limit.zip", "archive"},
        Fixture{"viewer.project.zip", "archive"},
        Fixture{"viewer.field-kit.tar", "archive"},
        Fixture{"viewer.field-notes.txt.gz", "archive"},
        Fixture{"viewer.field-kit.tar.gz", "archive"},
        Fixture{"viewer.pax-field-kit.tar", "archive"},
        Fixture{"viewer.console.exe", "binary"},
        Fixture{"viewer.field-station.elf", "binary"},
        Fixture{"viewer.hex.telemetry.bin", "binary"},
        Fixture{"viewer.csv", "table"},
        Fixture{"viewer.trailing-quote.csv", "table"},
        Fixture{"viewer.field-observations.csv", "table"},
        Fixture{"viewer.tsv", "table"},
        Fixture{"viewer.tab", "table"},
        Fixture{"viewer.mid", "midi"},
        Fixture{"viewer.midi", "midi"},
        Fixture{"viewer.ensemble.mid", "midi"},
        Fixture{"viewer.srt", "subtitle"},
        Fixture{"viewer.vtt", "subtitle"},
        Fixture{"viewer.field-notes.vtt", "subtitle"},
        Fixture{"viewer.ass", "subtitle"},
        Fixture{"viewer.ssa", "subtitle"},
        Fixture{"viewer.lrc", "subtitle"},
        Fixture{"viewer.sub", "subtitle"},
        Fixture{"viewer.arabic.ttf", "font"},
        Fixture{"font-fixture-cjk.otf", "font"},
        Fixture{"font-fixture-damaged.otf", "font"},
        Fixture{"viewer.svg", "image"},
        Fixture{"viewer.dense-solid.svg", "image"},
        Fixture{"viewer.watershed-map.svg", "image"},
        Fixture{"viewer.bmp", "image"},
        Fixture{"viewer.dib", "image", "viewer.bmp"},
        Fixture{"viewer.dds", "image"},
        Fixture{"viewer.exr", "image"},
        Fixture{"viewer.gif", "image"},
        Fixture{"viewer.ico", "image"},
        Fixture{"viewer.jpg", "image"},
        Fixture{"viewer.jpeg", "image"},
        Fixture{"viewer.alias.jpe", "image"},
        Fixture{"viewer.alias.jfif", "image"},
        Fixture{"viewer.jif", "image", "viewer.jpg"},
        Fixture{"viewer.jfi", "image", "viewer.jpg"},
        Fixture{"viewer.JPS", "image", "viewer.jpg"},
        Fixture{"viewer.ktx2", "image"},
        Fixture{"viewer.png", "image"},
        Fixture{"viewer.psd", "image"},
        Fixture{"viewer.qoi", "image"},
        Fixture{"viewer.tga", "image"},
        Fixture{"viewer.icb", "image", "viewer.tga"},
        Fixture{"viewer.vda", "image", "viewer.tga"},
        Fixture{"viewer.vst", "image", "viewer.tga"},
        Fixture{"viewer.tif", "image"},
        Fixture{"viewer.tiff", "image"},
        Fixture{"viewer.webp", "image"},
        Fixture{"viewer.synthetic-review.webp", "image"},
        Fixture{"viewer.icc-profile.webp", "image"},
        Fixture{"viewer.icc-profile.jpg", "image"},
        Fixture{"viewer.icc-profile-mluc.webp", "image"},
        Fixture{"viewer.xmp.webp", "image"},
        Fixture{"viewer.xmp.jpg", "image"},
        Fixture{"viewer.wav", "sound"},
        Fixture{"viewer.field-station.wav", "sound"},
        Fixture{"viewer.flac", "sound"},
        Fixture{"viewer.mp3", "sound"},
        Fixture{"viewer.aac", "sound"},
        Fixture{"viewer.ac3", "sound"},
        Fixture{"viewer.eac3", "sound"},
        Fixture{"viewer.ec3", "sound", "viewer.eac3"},
        Fixture{"viewer.dts", "sound"},
        Fixture{"viewer.huffman.dts", "sound"},
        Fixture{"viewer.ogg", "sound"},
        Fixture{"viewer.oga", "sound", "viewer.ogg"},
        Fixture{"viewer.flac.oga", "sound"},
        Fixture{"viewer.opus", "sound"},
        Fixture{"viewer.mp4", "video"},
        Fixture{"viewer.synthetic-field.mp4", "video"},
        Fixture{"viewer.m4v", "video", "glint-aac-mjpeg.mp4"},
        Fixture{"viewer.mov", "video", "glint-aac-mjpeg.mp4"},
        Fixture{"viewer.mkv", "video", "ffmpeg-h264-two-aac.mkv"},
        Fixture{"viewer.avi", "video"},
        Fixture{"viewer.mpeg4-mp3.avi", "video"},
        Fixture{"viewer.y4m", "video"},
        Fixture{"viewer.cmyk.jpg", "image"},
        Fixture{"viewer.progressive.jpg", "image"},
        Fixture{"viewer.animation.gif", "image"},
        Fixture{"viewer.animation.webp", "image"},
        Fixture{"viewer.animation.apng", "image"},
        Fixture{"viewer.surround.flac", "sound"},
        Fixture{"viewer.surround.eac3", "sound"},
        Fixture{"viewer.hybrid.opus", "sound"},
        Fixture{"viewer.h264.mp4", "video", "ffmpeg-h264-baseline.mp4"},
        Fixture{"viewer.hevc.mp4", "video"},
        Fixture{"viewer.raw.avi", "video"},
        Fixture{"viewer.rv40.mkv", "video", "rv40-legacy-clock.mkv"},
        Fixture{"viewer.json", "code"},
        Fixture{"viewer.xml", "code"},
        Fixture{"viewer.py", "code"},
        Fixture{"viewer.swg", "code"},
        Fixture{"viewer.rst", "text"},
        Fixture{"viewer.arabic.ttc", "font"},
        Fixture{"viewer.arabic.partial.ttc", "font"},
        Fixture{"viewer.pptx", "pptx"},
        Fixture{"viewer.ppsx", "pptx"},
        Fixture{"viewer.macros.pptm", "pptx"},
        Fixture{"viewer.odt", "odt"},
        Fixture{"viewer.legacy-manifest.odt", "odt"},
        Fixture{"viewer.christmas-carol.odt", "odt"},
        Fixture{"viewer.image.odt", "odt"},
        Fixture{"viewer.ods", "ods"},
        Fixture{"viewer.manifest-only.ods", "ods"},
        Fixture{"viewer.number-formats.ods", "ods"},
        Fixture{"viewer.navigation.ods", "ods"},
        Fixture{"viewer.monthly-budget.ods", "ods"},
        Fixture{"viewer.odp", "odp"},
        Fixture{"viewer.poi-sample.odp", "odp"},
        Fixture{"viewer.watershed.odp", "odp"},
        Fixture{"viewer.jar", "archive"},
        Fixture{"viewer.object-stream.pdf", "pdf"},
        Fixture{"viewer.rotation.pdf", "pdf"},
        Fixture{"viewer.jpeg.pdf", "pdf"},
        Fixture{"viewer.mixed-text-scan.pdf", "pdf"},
        Fixture{"viewer.ccitt.pdf", "pdf"},
        Fixture{"viewer.runs.docx", "docx"},
        Fixture{"viewer.damaged.docx", "docx"},
        Fixture{"viewer.inline.xlsx", "xlsx"},
        Fixture{"viewer.damaged.xlsx", "xlsx"},
        Fixture{"viewer.nested.cbz", "comic"},
        Fixture{"viewer.nested.epub", "epub"},
        Fixture{"viewer.damaged.epub", "epub"},
        Fixture{"viewer.apng", "image"},
        Fixture{"viewer.cur", "image"},
        Fixture{"viewer.slides.pptx", "pptx"},
        Fixture{"viewer.damaged.pptx", "pptx"},
        Fixture{"viewer.alternate-picture.rtf", "rtf"},
        Fixture{"viewer.default-styles.xlsx", "xlsx"},
        Fixture{"viewer.empty-cells.xlsx", "xlsx"},
        Fixture{"viewer.formats.xlsx", "xlsx"},
        Fixture{"viewer.formatted.pptx", "pptx"},
        Fixture{"viewer.formulas.xlsx", "xlsx"},
        Fixture{"viewer.geometry.pptx", "pptx"},
        Fixture{"viewer.navigation.epub", "epub"},
        Fixture{"viewer.navigation.ncx.epub", "epub"},
        Fixture{"viewer.pagebreak.docx", "docx"},
        Fixture{"viewer.pictures.pptx", "pptx"},
        Fixture{"viewer.pictures.rtf", "rtf"},
        Fixture{"viewer.sparse-rows.xlsx", "xlsx"},
        Fixture{"viewer.styles.docx", "docx"},
        Fixture{"viewer.wide-column.xlsx", "xlsx"},
        Fixture{"viewer.christmas-carol.epub", "epub"},
        Fixture{"viewer.poi-sample.docx", "docx"},
        Fixture{"viewer.monthly-budget.xlsx", "xlsx"},
        Fixture{"viewer.poi-sample.pptx", "pptx"},
        Fixture{"viewer.openmp-reference.pdf", "pdf"},
        Fixture{"viewer.archive.icons.png", "image"},
        Fixture{"viewer.archive.zip", "archive"},
        Fixture{"viewer.comic.cbz", "comic"},
        Fixture{"viewer.groove.mid", "midi"},
        Fixture{"viewer.hex", "text"},
        Fixture{"viewer.page.html", "html"},
        Fixture{"viewer.reading.srt", "subtitle"},
        Fixture{"viewer.field-notes.ipynb", "notebook"},
        Fixture{"viewer.field-display.ipynb", "notebook"}]
    let registry = createViewerPluginRegistry()
    for &item in Cases
    {
        let isAlias = item.aliasOf.count != 0
        let path    = isAlias ? isolatedScopeFixture(item.aliasOf, asName: item.name) : scopeTestDataPath(item.name)
        defer if isAlias do
            discardIsolatedScopeFixture(path)
        Swag.require(File.exists(path), item.name)
        let choices = registry.choices(path)
        Swag.require(not choices.isEmpty() and choices[0].key == item.viewer, item.name)
    }
}

// Dense painted contours retain the hole and appear throughout the image.
#test
{
    let image = expect Picture.loadViewerImage(scopeTestDataPath("viewer.dense-solid.svg"))
    Swag.require(image.width == 76 and image.height == 84)
    var ink: u64
    for y in image.height do
        for x in image.width where image.pixelColor(x, y).a == 255 do
            ink += 1
    Swag.require(ink == 528 * 4 + 12 * 12 - 6 * 6)
}

private func requireStereoSignal(sound: const *SoundFile, encoding: SoundFileEncoding, sampleRate: u32)
{
    Swag.require(sound.sampleEncoding() == encoding and sound.sampleRateHz() == sampleRate and sound.numChannels() == 2)
    var channels: [2] bool
    var count: u64
    let frames = Math.min(sound.sampleFrameCount(), cast(u64, sampleRate) / 4)
    expect sound.decodePcm16(0, frames, func|&channels, &count|(samples)
    {
        for sample, index in samples where sample do
            channels[index % 2] = true
        count += samples.count
        return true
    })
    Swag.require(count == frames * 2 and channels[0] and channels[1])
}

// The two packet formats preserve a decodable stereo signal.
#test
{
    let dts  = expect SoundFile.load(scopeTestDataPath("viewer.huffman.dts"))
    let flac = expect SoundFile.load(scopeTestDataPath("viewer.flac.oga"))
    requireStereoSignal(&dts, .Dts, 44_100)
    requireStereoSignal(&flac, .Flac, 44_100)
}

// The picture and the Layer III track both reach the viewer through the AVI reader.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.mpeg4-mp3.avi"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "video")
    let view = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    waitForVideoAudio(view, 1)
    Swag.require(view.hasFrame and view.video.width() == 64 and view.video.height() == 48)
    requireStereoSignal(unwrap view.audio, .Mp3, 48_000)
}

// Pixel variants are actual decodable images, including hand-authored QOI and renamed aliases.
#test
{
    const Cases: [27] string = [
        "viewer.bmp", "viewer.dds", "viewer.exr", "viewer.gif",
        "viewer.ico", "viewer.jpg", "viewer.jpeg", "viewer.alias.jpe", "viewer.alias.jfif", "viewer.ktx2", "viewer.png",
        "viewer.psd", "viewer.qoi", "viewer.tga", "viewer.tif", "viewer.tiff",
        "viewer.webp", "viewer.cmyk.jpg", "viewer.progressive.jpg", "viewer.animation.apng",
        "viewer.apng", "viewer.cur", "viewer.icc-profile.webp", "viewer.icc-profile.jpg",
        "viewer.icc-profile-mluc.webp", "viewer.xmp.webp", "viewer.xmp.jpg"]
    for name in Cases
    {
        let image = catch Image.load(scopeTestDataPath(name))
        {
            Swag.require(false, name)
            continue
        }

        Swag.require(image.isValid(), name)
    }

    let qoi = expect Image.load(scopeTestDataPath("viewer.qoi"))
    Swag.require(qoi.width == 2 and qoi.height == 2)
    Swag.require(qoi.pixelColor(0, 0) == Color{r: 30, g: 92, b: 150, a: 255})
    Swag.require(qoi.pixelColor(1, 0) == Color{r: 232, g: 174, b: 57, a: 255})
    Swag.require(qoi.pixelColor(0, 1) == Color{r: 58, g: 145, b: 96, a: 255})
    Swag.require(qoi.pixelColor(1, 1) == Color{r: 176, g: 76, b: 85, a: 192})

    var cursor = expect ImageReader.load(scopeTestDataPath("viewer.cur"))
    Swag.require(cursor.info.frames.count == 2)
    let largeCursor = expect cursor.read(0)
    let smallCursor = expect cursor.read(1)
    Swag.require(largeCursor.width == 4 and largeCursor.height == 4)
    Swag.require(smallCursor.width == 2 and smallCursor.height == 2)

    let icons = expect Image.load(scopeTestDataPath("viewer.archive.icons.png"))
    Swag.require(icons.width == 48 and icons.height == 16)
    Swag.require(icons.pixelColor(4, 9) == Color{r: 244, g: 184, b: 54, a: 255})
    Swag.require(icons.pixelColor(20, 6) == Color{r: 44, g: 121, b: 157, a: 255})
    Swag.require(icons.pixelColor(36, 6) == Color{r: 74, g: 139, b: 85, a: 255})
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Viewers

private struct Fixture
{
    name: string
    viewer: string
}

// A collection wraps a real face and still exposes its character map to the font reader.
#test
{
    let bytes = expect File.readAllBytes(scopeTestDataPath("viewer.ttc"))
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()
    Swag.require(face.hasChar('A'))
}

// Every canonical format fixture and named variant selects its intended reading surface.
#test
{
    const Cases: [116] Fixture = [
        Fixture{"viewer.txt", "text"},
        Fixture{"viewer.cpp", "code"},
        Fixture{"viewer.md", "markdown"},
        Fixture{"viewer.markdown", "markdown"},
        Fixture{"viewer.html", "html"},
        Fixture{"viewer.htm", "html"},
        Fixture{"viewer.xhtml", "html"},
        Fixture{"viewer.pdf", "pdf"},
        Fixture{"viewer.epub", "epub"},
        Fixture{"viewer.docx", "docx"},
        Fixture{"viewer.formatted.docx", "docx"},
        Fixture{"viewer.rtf", "rtf"},
        Fixture{"viewer.unicode.rtf", "rtf"},
        Fixture{"viewer.table.rtf", "rtf"},
        Fixture{"viewer.destinations.rtf", "rtf"},
        Fixture{"viewer.damaged.rtf", "rtf"},
        Fixture{"viewer.libreoffice.rtf", "rtf"},
        Fixture{"viewer.xlsx", "xlsx"},
        Fixture{"viewer.cbz", "comic"},
        Fixture{"viewer.zip", "archive"},
        Fixture{"viewer.console.exe", "binary"},
        Fixture{"viewer.csv", "table"},
        Fixture{"viewer.tsv", "table"},
        Fixture{"viewer.tab", "table"},
        Fixture{"viewer.mid", "midi"},
        Fixture{"viewer.midi", "midi"},
        Fixture{"viewer.srt", "subtitle"},
        Fixture{"viewer.vtt", "subtitle"},
        Fixture{"viewer.ass", "subtitle"},
        Fixture{"viewer.ssa", "subtitle"},
        Fixture{"viewer.lrc", "subtitle"},
        Fixture{"viewer.sub", "subtitle"},
        Fixture{"viewer.ttf", "font"},
        Fixture{"viewer.svg", "image"},
        Fixture{"viewer.bmp", "image"},
        Fixture{"viewer.dds", "image"},
        Fixture{"viewer.exr", "image"},
        Fixture{"viewer.gif", "image"},
        Fixture{"viewer.ico", "image"},
        Fixture{"viewer.jpg", "image"},
        Fixture{"viewer.jpeg", "image"},
        Fixture{"viewer.ktx2", "image"},
        Fixture{"viewer.png", "image"},
        Fixture{"viewer.psd", "image"},
        Fixture{"viewer.qoi", "image"},
        Fixture{"viewer.tga", "image"},
        Fixture{"viewer.tif", "image"},
        Fixture{"viewer.tiff", "image"},
        Fixture{"viewer.webp", "image"},
        Fixture{"viewer.wav", "sound"},
        Fixture{"viewer.flac", "sound"},
        Fixture{"viewer.mp3", "sound"},
        Fixture{"viewer.aac", "sound"},
        Fixture{"viewer.ac3", "sound"},
        Fixture{"viewer.eac3", "sound"},
        Fixture{"viewer.ec3", "sound"},
        Fixture{"viewer.dts", "sound"},
        Fixture{"viewer.ogg", "sound"},
        Fixture{"viewer.oga", "sound"},
        Fixture{"viewer.opus", "sound"},
        Fixture{"viewer.mp4", "video"},
        Fixture{"viewer.m4v", "video"},
        Fixture{"viewer.mov", "video"},
        Fixture{"viewer.mkv", "video"},
        Fixture{"viewer.avi", "video"},
        Fixture{"viewer.y4m", "video"},
        Fixture{"viewer.cmyk.jpg", "image"},
        Fixture{"viewer.progressive.jpg", "image"},
        Fixture{"viewer.animation.gif", "image"},
        Fixture{"viewer.animation.webp", "image"},
        Fixture{"viewer.animation.apng", "image"},
        Fixture{"viewer.surround.flac", "sound"},
        Fixture{"viewer.surround.eac3", "sound"},
        Fixture{"viewer.hybrid.opus", "sound"},
        Fixture{"viewer.h264.mp4", "video"},
        Fixture{"viewer.hevc.mp4", "video"},
        Fixture{"viewer.raw.avi", "video"},
        Fixture{"viewer.rv40.mkv", "video"},
        Fixture{"viewer.json", "code"},
        Fixture{"viewer.xml", "code"},
        Fixture{"viewer.py", "code"},
        Fixture{"viewer.swg", "code"},
        Fixture{"viewer.rst", "text"},
        Fixture{"viewer.ttc", "font"},
        Fixture{"viewer.pptx", "pptx"},
        Fixture{"viewer.odt", "archive"},
        Fixture{"viewer.ods", "archive"},
        Fixture{"viewer.odp", "archive"},
        Fixture{"viewer.jar", "archive"},
        Fixture{"viewer.object-stream.pdf", "pdf"},
        Fixture{"viewer.rotation.pdf", "pdf"},
        Fixture{"viewer.jpeg.pdf", "pdf"},
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
    ]
    let registry = createViewerPluginRegistry()
    for &item in Cases
    {
        let path = scopeTestDataPath(item.name)
        Swag.require(File.exists(path), item.name)
        let choices = registry.choices(path)
        Swag.require(not choices.isEmpty() and choices[0].key == item.viewer, item.name)
    }
}

// Pixel variants are actual decodable images, including hand-authored QOI and renamed aliases.
#test
{
    const Cases: [20] string = [
        "viewer.bmp", "viewer.dds", "viewer.exr", "viewer.gif",
        "viewer.ico", "viewer.jpg", "viewer.jpeg", "viewer.ktx2", "viewer.png",
        "viewer.psd", "viewer.qoi", "viewer.tga", "viewer.tif", "viewer.tiff",
        "viewer.webp", "viewer.cmyk.jpg", "viewer.progressive.jpg", "viewer.animation.apng",
        "viewer.apng", "viewer.cur",
    ]
    for name in Cases
    {
        let image = catch Image.load(scopeTestDataPath(name))
        {
            Swag.require(false, name)
            continue
        }
        Swag.require(image.isValid(), name)
    }
}

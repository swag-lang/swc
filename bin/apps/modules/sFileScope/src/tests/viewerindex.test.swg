#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The compiled registry keeps the format-specific order, basic text fallback, and wildcard viewer.
#test
{
    let textFile   = Gui.Testing.tempFilePath("filescope-index-", ".unknown")
    let binaryFile = Gui.Testing.tempFilePath("filescope-index-", ".png")
    defer discard catch File.delete(textFile)
    defer discard catch File.delete(binaryFile)
    expect File.writeAllBytes(textFile, "plain UTF-8 text")
    expect File.writeAllBytes(binaryFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    let index = createViewerIndex()
    @assert(index.specs.count == 10)
    for spec in index.specs do
        @assert(spec.create != null and !spec.extensions.isEmpty())

    let picture = index.choices(binaryFile)
    @assert(picture.count == 2)
    @assert(picture[0].name == "Image")
    @assert(picture[1].name == "Hexadecimal")

    let unknown = index.choices(textFile)
    @assert(unknown.count == 2)
    @assert(unknown[0].kind == .BasicText)
    @assert(unknown[1].name == "Hexadecimal")
    @assert(index.explicitlySupports("clip.gif"))
    @assert(!index.explicitlySupports("clip.bin"))
}

#test
{
    let index = createViewerIndex()
    @assert(index.explicitlySupports("Makefile"))
    @assert(index.explicitlySupports("DOCKERFILE"))

    let html = index.choices("page.html")
    @assert(html[0].name == "HTML" and html[1].name == "Code")
    @assert(index.choices("Makefile")[0].name == "Code")
    @assert(index.choices("Dockerfile")[0].name == "Code")

    let fontChoices = index.choices("family.ttf")
    @assert(fontChoices[0].name == "Font" and fontChoices[1].name == "Hexadecimal")
    @assert(index.choices("outlines.otf")[0].name == "Binary")

    let mp4Choices = index.choices("movie.mp4")
    @assert(mp4Choices[0].name == "Video" and mp4Choices[1].name == "Binary" and mp4Choices[2].name == "Hexadecimal")
}

// "The same kind" to folder navigation means one format viewer claims both files, or neither
// file is claimed and the extensions agree.
#test
{
    let index = createViewerIndex()
    @assert(index.sharesViewer("a.png", "B.JPG"))
    @assert(!index.sharesViewer("a.png", "b.wav"))
    @assert(index.sharesViewer("x.foo", "y.FOO"))
    @assert(!index.sharesViewer("x.foo", "y.bar"))
    @assert(!index.sharesViewer("a.png", "x.foo"))
}

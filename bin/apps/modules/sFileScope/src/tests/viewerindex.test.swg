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
    @assert(index.specs.count == 11)
    for spec in index.specs do
        @assert(spec.create != null and !spec.extensions.isEmpty())

    let picture = index.choices(binaryFile)
    @assert(picture.count == 3)
    @assert(picture[0].name == "Image")
    @assert(picture[1].name == "Binary")
    @assert(picture[2].name == "Hexadecimal")

    let unknown = index.choices(textFile)
    @assert(unknown.count == 3)
    @assert(unknown[0].kind == .BasicText)
    @assert(unknown[1].name == "Binary")
    @assert(unknown[2].name == "Hexadecimal")
    @assert(index.explicitlySupports("clip.gif"))
    @assert(!index.explicitlySupports("clip.bin"))
}

#test
{
    let index = createViewerIndex()
    @assert(index.explicitlySupports("Makefile"))
    @assert(index.explicitlySupports("DOCKERFILE"))
    @assert(index.explicitlySupports("CMakeLists.txt"))
    @assert(index.explicitlySupports(".gitignore"))

    let html = index.choices("page.html")
    @assert(html[0].name == "HTML" and html[1].name == "Code")
    @assert(index.choices("Makefile")[0].name == "Code")
    @assert(index.choices("Dockerfile")[0].name == "Code")
    @assert(index.choices("CMakeLists.txt")[0].name == "Code")
    @assert(index.choices(".gitignore")[0].name == "Code")

    let tableChoices = index.choices("data.csv")
    @assert(tableChoices[0].name == "Table" and tableChoices[1].name == "Binary" and tableChoices[2].name == "Hexadecimal")

    let fontChoices = index.choices("family.ttf")
    @assert(fontChoices[0].name == "Font" and fontChoices[1].name == "Binary" and fontChoices[2].name == "Hexadecimal")
    @assert(index.choices("outlines.otf")[0].name == "Binary")

    let mp4Choices = index.choices("movie.mp4")
    @assert(mp4Choices[0].name == "Video" and mp4Choices[1].name == "Binary" and mp4Choices[2].name == "Hexadecimal")

    let matroskaChoices = index.choices("movie.mkv")
    @assert(matroskaChoices[0].name == "Video" and matroskaChoices[1].name == "Binary" and matroskaChoices[2].name == "Hexadecimal")

    let midiChoices = index.choices("score.mid")
    @assert(midiChoices[0].name == "Binary" and midiChoices[1].name == "Hexadecimal")

    const SoundFiles: [7] string = ["sound.wav", "sound.flac", "sound.mp3", "sound.aac", "sound.ac3", "sound.eac3", "sound.ec3"]
    for file in SoundFiles do
        @assert(index.choices(file)[0].key == "sound")
}

// The interpreter line claims an extensionless script and drives its syntax coloring.
#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-shebang-", "")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "#!/usr/bin/env python3\nprint('hello')\n")

    let index   = createViewerIndex()
    let choices = index.choices(fileName)
    @assert(choices[0].key == "code" and choices[1].kind == .BasicText and choices[2].key == "binary" and choices[3].key == "hex")
    @assert(codeLanguage(fileName) == .Python)
}

// Every viewer carries the stable identity a remembered choice is written under, and the glyph
// the selector shows beside its name. Neither is ever shared: the persisted state names exactly
// one viewer, and so does the mark a reader picks the viewer by.
#test
{
    let index = createViewerIndex()
    for spec, i in index.specs
    {
        @assert(!spec.key.isEmpty() and spec.key != BasicTextViewerKey)
        @assert(spec.key == spec.key.toLower())
        for other, j in index.specs where j > i do
            @assert(spec.key != other.key and spec.icon != other.icon)
    }

    let movie = index.choices("movie.mp4")
    @assert(movie[0].key == "video" and movie[0].icon == .Video)
    @assert(movie[1].key == "binary" and movie[1].icon == .Binary)
    @assert(movie[2].key == "hex" and movie[2].icon == .Hex)

    // The host's own surface answers for a readable file, under a key of the same vocabulary.
    let plain = Gui.Testing.tempFilePath("filescope-keys-", ".unknown")
    defer discard catch File.delete(plain)
    expect File.writeAllBytes(plain, "plain UTF-8 text")
    let readable = index.choices(plain)
    @assert(readable[0].kind == .BasicText)
    @assert(readable[0].key == BasicTextViewerKey and readable[0].icon == .Text)
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

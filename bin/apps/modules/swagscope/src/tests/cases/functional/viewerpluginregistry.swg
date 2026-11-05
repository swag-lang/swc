#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func viewerRegistryFixturePath(name: string)->String => Path.combine(Path.combine(testSourceRoot(#curlocation), "datas"), name)

private func choicePlugin(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->const *Viewer.Plugin => &registry.plugins[choice.pluginIndex]

private func choiceName(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->string => choicePlugin(registry, choice).displayName()

private func createTestPlugin(host: Viewer.Host)
{
    host.attachView(Wnd.create'Wnd(host.contentParent()))
}

private func testPlugin(key = "custom", selector = ".plug")->Viewer.Plugin
{
    var result: #returntype
    result.key          = key
    result.staticName   = "Custom"
    result.iconAtlas    = viewerIcons()
    result.create       = &createTestPlugin
    result.smokeFixture = "custom.plug"
    result.addSelectors(selector)
    return result
}

// A name the registry does not know is not the end of the question. Bytes that read as text reach
// the text surface whatever the file is called, and bytes that do not stay with the fallbacks.
#test
{
    let textFile   = Gui.Testing.tempFilePath("scope-index-", ".unknown")
    let binaryFile = Gui.Testing.tempFilePath("scope-index-", ".png")
    defer discard catch File.delete(textFile)
    defer discard catch File.delete(binaryFile)
    expect File.writeAllBytes(textFile, "plain UTF-8 text")
    expect File.writeAllBytes(binaryFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    let registry = createViewerPluginRegistry()
    Swag.require(registry.plugins.count == 15)
    for plugin in registry.plugins do
        Swag.require(plugin.apiVersion == Viewer.ApiVersion and
                     plugin.create != null and
                     plugin.iconAtlas != null)

    let picture = registry.choices(binaryFile)
    Swag.require(picture.count == 3)
    Swag.require(choiceName(&registry, &picture[0]) == "Image")
    Swag.require(choiceName(&registry, &picture[1]) == "Binary")
    Swag.require(choiceName(&registry, &picture[2]) == "Hexadecimal")

    let unknown = registry.choices(textFile)
    Swag.require(unknown.count == 3)
    Swag.require(unknown[0].key == PlainText.ViewerKey)
    Swag.require(choiceName(&registry, &unknown[1]) == "Binary")
    Swag.require(choiceName(&registry, &unknown[2]) == "Hexadecimal")
    Swag.require(registry.explicitlySupports("clip.gif"))
    Swag.require(not registry.explicitlySupports("clip.bin"))
}

// Every descriptor carries one immutable smoke basename, and that file discovers the descriptor
// through the same generic selector and probe phases used by the application.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        Swag.require((Path.fileName(plugin.smokeFixture.toString()) orelse "") == plugin.smokeFixture.toString())
        let fixture = viewerRegistryFixturePath(plugin.smokeFixture)
        Swag.require(File.exists(fixture))

        var found: bool
        for choice in registry.choices(fixture) where choice.key == plugin.key
        {
            found = true
            break
        }

        Swag.require(found)
        for other, j in registry.plugins where j > i do
            Swag.require(plugin.smokeFixture != other.smokeFixture)
    }
}

#test
{
    let registry = createViewerPluginRegistry()
    Swag.require(registry.explicitlySupports("Makefile"))
    Swag.require(registry.explicitlySupports("DOCKERFILE"))
    Swag.require(registry.explicitlySupports("CMakeLists.txt"))
    Swag.require(registry.explicitlySupports(".gitignore"))

    let html = registry.choices("page.html")
    Swag.require(choiceName(&registry, &html[0]) == "HTML" and choiceName(&registry, &html[1]) == "Code")
    Swag.require(choiceName(&registry, &registry.choices("Makefile")[0]) == "Code")
    Swag.require(choiceName(&registry, &registry.choices("Dockerfile")[0]) == "Code")
    Swag.require(choiceName(&registry, &registry.choices("CMakeLists.txt")[0]) == "Code")
    Swag.require(choiceName(&registry, &registry.choices(".gitignore")[0]) == "Code")

    let tableChoices = registry.choices("data.csv")
    Swag.require(choiceName(&registry, &tableChoices[0]) == "Table" and
                 tableChoices[1].key == "binary" and
                 tableChoices[2].key == "hex")
    Swag.require(registry.choices("family.ttf")[0].key == "font")
    Swag.require(registry.choices("outlines.otf")[0].key == "binary")
    Swag.require(registry.choices("movie.mp4")[0].key == "video")
    Swag.require(registry.choices("movie.mkv")[0].key == "video")
    Swag.require(registry.choices("score.mid")[0].key == "midi")
    Swag.require(registry.choices("dialogue.srt")[0].key == "subtitle")
    let openDocumentChoices = registry.choices("budget.ods")
    Swag.require(openDocumentChoices[0].key == "archive" and
                 openDocumentChoices[1].key == "binary" and
                 openDocumentChoices[2].key == "hex")
    Swag.require(registry.choices("bundle.zip")[0].key == "archive")

    const SoundFiles: [11] string = ["sound.wav", "sound.flac", "sound.mp3", "sound.aac", "sound.ac3", "sound.eac3", "sound.ec3", "sound.dts", "sound.ogg", "sound.oga", "sound.opus"]
    for file in SoundFiles do
        Swag.require(registry.choices(file)[0].key == "sound")
}

// The interpreter line claims an extensionless script before wildcard plugins.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-shebang-", "")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "#!/usr/bin/env python3\nprint('hello')\n")

    let registry = createViewerPluginRegistry()
    let choices  = registry.choices(fileName)
    Swag.require(choices[0].key == "code" and
                 choices[1].key == PlainText.ViewerKey and
                 choices[2].key == "binary" and
                 choices[3].key == "hex")
    Swag.require(Code.detectLanguage(fileName) == .Python)
}

// A format whose bytes are text is offered twice: as the document it is, then as the source it is
// made of. A format whose bytes are not stays with the viewer that understands them.
#test
{
    let registry = createViewerPluginRegistry()

    let markdown = registry.choices(viewerRegistryFixturePath("comprehensive.md"))
    Swag.require(markdown.count == 4)
    Swag.require(markdown[0].key == "markdown" and
                 markdown[1].key == PlainText.ViewerKey and
                 markdown[2].key == "binary" and
                 markdown[3].key == "hex")

    let source = registry.choices(viewerRegistryFixturePath("sample.cpp"))
    Swag.require(source[0].key == "code" and source[1].key == PlainText.ViewerKey)

    let table = registry.choices(viewerRegistryFixturePath("viewer.csv"))
    Swag.require(table[0].key == "table" and table[1].key == PlainText.ViewerKey)

    let subtitles = registry.choices(viewerRegistryFixturePath("viewer.srt"))
    Swag.require(subtitles[0].key == "subtitle" and subtitles[1].key == PlainText.ViewerKey)

    let page = registry.choices(viewerRegistryFixturePath("viewer.html"))
    Swag.require(page[0].key == "html" and page[1].key == "code" and page[2].key == PlainText.ViewerKey)

    for choice in registry.choices(viewerRegistryFixturePath("viewer.pdf")) do
        Swag.require(choice.key != PlainText.ViewerKey)
    for choice in registry.choices(viewerRegistryFixturePath("segoeui.ttf")) do
        Swag.require(choice.key != PlainText.ViewerKey)
}

// A name that says nothing leaves the file to say it. Every format that opens on a signature is
// recognized through a copy renamed to an extension nothing claims.
#test
{
    const Fixtures: [5] string = ["viewer.pdf", "viewer.mid", "segoeui.ttf", "viewer.archive.zip", "viewer.html"]
    const Keys:     [5] string = ["pdf", "midi", "font", "archive", "html"]

    let registry = createViewerPluginRegistry()
    for fixture, index in Fixtures
    {
        let renamed = Gui.Testing.tempFilePath("scope-sniff-", ".unknown")
        defer discard catch File.delete(renamed)
        expect File.duplicate(renamed, viewerRegistryFixturePath(fixture))
        Swag.require(registry.choices(renamed)[0].key == Keys[index])
    }
}

// Text is text whichever encoding spells it, and a file with no extension at all is still read
// rather than dumped as bytes.
#test
{
    var utf16: Array'u8
    utf16.add(0xFF)
    utf16.add(0xFE)
    for c in "a wide export nothing claims"
    {
        utf16.add(cast(u8, c))
        utf16.add(0)
    }

    let fileName = Gui.Testing.tempFilePath("scope-wide-", "")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, utf16.toSlice())

    let registry = createViewerPluginRegistry()
    Swag.require(registry.choices(fileName)[0].key == PlainText.ViewerKey)

    // Deciding an encoding is not accepting the file: bytes that decode into control characters
    // are not offered as a page of text.
    var binary: Array'u8
    for i in 512'u32 do
        binary.add(cast(u8, ((i * 7) & 0xFF)))
    let opaque = Gui.Testing.tempFilePath("scope-opaque-", "")
    defer discard catch File.delete(opaque)
    expect File.writeAllBytes(opaque, binary.toSlice())
    Swag.require(registry.choices(opaque)[0].key == "binary")
}

// Stable keys and icon contexts belong to descriptors rather than hard-coded choice variants.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        Swag.require(not plugin.key.isEmpty() and plugin.key == plugin.key.toLower())
        for other, j in registry.plugins where j > i do
            Swag.require(plugin.key != other.key and plugin.iconIndex != other.iconIndex)
    }

    let movie = registry.choices("movie.mp4")
    Swag.require(movie[0].key == "video" and ViewerIconValues[choicePlugin(&registry, &movie[0]).iconIndex] == .Video)
    Swag.require(movie[1].key == "binary" and ViewerIconValues[choicePlugin(&registry, &movie[1]).iconIndex] == .Binary)
    Swag.require(movie[2].key == "hex" and ViewerIconValues[choicePlugin(&registry, &movie[2]).iconIndex] == .Hex)

    let plain = Gui.Testing.tempFilePath("scope-keys-", ".txt")
    defer discard catch File.delete(plain)
    expect File.writeAllBytes(plain, "plain UTF-8 text")
    let readable = registry.choices(plain)
    Swag.require(readable[0].key == PlainText.ViewerKey)
    Swag.require(ViewerIconValues[choicePlugin(&registry, &readable[0]).iconIndex] == .Text)
}

// A descriptor unknown to the built-in registry participates in discovery and creation without
// adding a choice kind, editing the window, or learning any host implementation type.
#test
{
    var registry = createViewerPluginRegistry()
    expect registry.register(testPlugin())
    let choices = registry.choices("sample.plug")
    Swag.require(choices[0].key == "custom")

    var host: Testing.HeadlessHost
    host.setup(320, 200)
    var session = openTestViewer(choicePlugin(&registry, &choices[0])[], &host.root, "sample.plug")
    Swag.require(session.view != null and session.failureReason.isEmpty())

    var duplicate = testPlugin()
    var duplicateErrorOutcome: Swag.Error
    discard catch registry.register(#move duplicate) as duplicateErrorOutcome
    let duplicateError = duplicateErrorOutcome.value()
    Swag.require(duplicateError != null)

    var incompatible = testPlugin("future", ".future")
    incompatible.apiVersion = Viewer.ApiVersion + 1
    var versionErrorOutcome: Swag.Error
    discard catch registry.register(#move incompatible) as versionErrorOutcome
    let versionError = versionErrorOutcome.value()
    Swag.require(versionError != null)
}

// Folder navigation groups files by explicitly registered plugins, with extension equality only
// when neither file has a named plugin.
#test
{
    let registry = createViewerPluginRegistry()
    Swag.require(registry.sharesViewer("a.png", "B.JPG"))
    Swag.require(not registry.sharesViewer("a.png", "b.wav"))
    Swag.require(registry.sharesViewer("x.foo", "y.FOO"))
    Swag.require(not registry.sharesViewer("x.foo", "y.bar"))
    Swag.require(not registry.sharesViewer("a.png", "x.foo"))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func viewerRegistryFixturePath(name: string)->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)
}

private func choicePlugin(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->const *FileViewer.Plugin
{
    return &registry.plugins[choice.pluginIndex]
}

private func choiceName(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->string
{
    return choicePlugin(registry, choice).displayName()
}

private func testPluginIcon(parent: *Wnd, size: f32, data: u64)->Icon
{
    discard parent
    discard size
    discard data
    return {}
}

private func createTestPlugin(host: FileViewer.Host)
{
    host.attachView(Wnd.create'Wnd(host.contentParent()))
}

private func testPlugin(key = "custom", selector = ".plug")->FileViewer.Plugin
{
    var result: retval
    result.key          = key
    result.staticName   = "Custom"
    result.icon         = &testPluginIcon
    result.create       = &createTestPlugin
    result.smokeFixture = "custom.plug"
    result.selectors.add(String.from(selector))
    return result
}

// The registry treats every built-in, including basic text, as an ordinary plugin descriptor.
#test
{
    let textFile   = Gui.Testing.tempFilePath("scope-index-", ".unknown")
    let binaryFile = Gui.Testing.tempFilePath("scope-index-", ".png")
    defer discard catch File.delete(textFile)
    defer discard catch File.delete(binaryFile)
    expect File.writeAllBytes(textFile, "plain UTF-8 text")
    expect File.writeAllBytes(binaryFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    let registry = createViewerPluginRegistry()
    @assert(registry.plugins.count == 14)
    for plugin in registry.plugins do
        @assert(plugin.apiVersion == FileViewer.ViewerApiVersion and plugin.create != null and plugin.icon != null)

    let picture = registry.choices(binaryFile)
    @assert(picture.count == 3)
    @assert(choiceName(&registry, &picture[0]) == "Image")
    @assert(choiceName(&registry, &picture[1]) == "Binary")
    @assert(choiceName(&registry, &picture[2]) == "Hexadecimal")

    let unknown = registry.choices(textFile)
    @assert(unknown.count == 3 and unknown[0].key == BasicTextViewerKey)
    @assert(choiceName(&registry, &unknown[1]) == "Binary")
    @assert(choiceName(&registry, &unknown[2]) == "Hexadecimal")
    @assert(registry.explicitlySupports("clip.gif"))
    @assert(!registry.explicitlySupports("clip.bin"))
}

// Every descriptor carries one immutable smoke basename, and that file discovers the descriptor
// through the same generic selector and probe phases used by the application.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        @assert((Path.fileName(plugin.smokeFixture.toString()) orelse "") == plugin.smokeFixture.toString())
        let fixture = viewerRegistryFixturePath(plugin.smokeFixture.toString())
        @assert(File.exists(fixture))

        var found: bool
        for choice in registry.choices(fixture.toString()) where choice.key == plugin.key
        {
            found = true
            break
        }

        @assert(found)
        for other, j in registry.plugins where j > i do
            @assert(plugin.smokeFixture != other.smokeFixture)
    }
}

#test
{
    let registry = createViewerPluginRegistry()
    @assert(registry.explicitlySupports("Makefile"))
    @assert(registry.explicitlySupports("DOCKERFILE"))
    @assert(registry.explicitlySupports("CMakeLists.txt"))
    @assert(registry.explicitlySupports(".gitignore"))

    let html = registry.choices("page.html")
    @assert(choiceName(&registry, &html[0]) == "HTML" and choiceName(&registry, &html[1]) == "Code")
    @assert(choiceName(&registry, &registry.choices("Makefile")[0]) == "Code")
    @assert(choiceName(&registry, &registry.choices("Dockerfile")[0]) == "Code")
    @assert(choiceName(&registry, &registry.choices("CMakeLists.txt")[0]) == "Code")
    @assert(choiceName(&registry, &registry.choices(".gitignore")[0]) == "Code")

    let tableChoices = registry.choices("data.csv")
    @assert(choiceName(&registry, &tableChoices[0]) == "Table" and tableChoices[1].key == "binary" and tableChoices[2].key == "hex")
    @assert(registry.choices("family.ttf")[0].key == "font")
    @assert(registry.choices("outlines.otf")[0].key == "binary")
    @assert(registry.choices("movie.mp4")[0].key == "video")
    @assert(registry.choices("movie.mkv")[0].key == "video")
    @assert(registry.choices("score.mid")[0].key == "midi")
    @assert(registry.choices("dialogue.srt")[0].key == "subtitle")

    const SoundFiles: [11] string = ["sound.wav", "sound.flac", "sound.mp3", "sound.aac", "sound.ac3", "sound.eac3", "sound.ec3", "sound.dts", "sound.ogg", "sound.oga", "sound.opus"]
    for file in SoundFiles do
        @assert(registry.choices(file)[0].key == "sound")
}

// The interpreter line claims an extensionless script before readable-text and wildcard plugins.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-shebang-", "")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "#!/usr/bin/env python3\nprint('hello')\n")

    let registry = createViewerPluginRegistry()
    let choices  = registry.choices(fileName)
    @assert(choices[0].key == "code" and choices[1].key == BasicTextViewerKey and choices[2].key == "binary" and choices[3].key == "hex")
    @assert(codeLanguage(fileName) == .Python)
}

// Stable keys and icon contexts belong to descriptors rather than hard-coded choice variants.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        @assert(!plugin.key.isEmpty() and plugin.key == plugin.key.toLower())
        for other, j in registry.plugins where j > i do
            @assert(plugin.key != other.key and plugin.iconData != other.iconData)
    }

    let movie = registry.choices("movie.mp4")
    @assert(movie[0].key == "video" and cast(ViewerIcons) choicePlugin(&registry, &movie[0]).iconData == .Video)
    @assert(movie[1].key == "binary" and cast(ViewerIcons) choicePlugin(&registry, &movie[1]).iconData == .Binary)
    @assert(movie[2].key == "hex" and cast(ViewerIcons) choicePlugin(&registry, &movie[2]).iconData == .Hex)

    let plain = Gui.Testing.tempFilePath("scope-keys-", ".unknown")
    defer discard catch File.delete(plain)
    expect File.writeAllBytes(plain, "plain UTF-8 text")
    let readable = registry.choices(plain)
    @assert(readable[0].key == BasicTextViewerKey)
    @assert(cast(ViewerIcons) choicePlugin(&registry, &readable[0]).iconData == .Text)
}

// A descriptor unknown to the built-in registry participates in discovery and creation without
// adding a choice kind, editing the window, or learning any host implementation type.
#test
{
    var registry = createViewerPluginRegistry()
    expect registry.register(testPlugin())
    let choices = registry.choices("sample.plug")
    @assert(choices[0].key == "custom")

    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    var session = openTestViewer(choicePlugin(&registry, &choices[0]).create, &host.root, "sample.plug")
    @assert(session.view != null and session.failureReason.isEmpty())

    var duplicate = testPlugin()
    discard catch registry.register(#move duplicate) as duplicateError
    @assert(duplicateError != null)

    var incompatible = testPlugin("future", ".future")
    incompatible.apiVersion = FileViewer.ViewerApiVersion + 1
    discard catch registry.register(#move incompatible) as versionError
    @assert(versionError != null)
}

// Folder navigation groups files by explicitly registered plugins, with extension equality only
// when neither file has a named plugin.
#test
{
    let registry = createViewerPluginRegistry()
    @assert(registry.sharesViewer("a.png", "B.JPG"))
    @assert(!registry.sharesViewer("a.png", "b.wav"))
    @assert(registry.sharesViewer("x.foo", "y.FOO"))
    @assert(!registry.sharesViewer("x.foo", "y.bar"))
    @assert(!registry.sharesViewer("a.png", "x.foo"))
}

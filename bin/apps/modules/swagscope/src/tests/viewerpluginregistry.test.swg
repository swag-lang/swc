#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func viewerRegistryFixturePath(name: string)->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)
}

private func choicePlugin(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->const *Viewer.Plugin
{
    return &registry.plugins[choice.pluginIndex]
}

private func choiceName(registry: const *ViewerPluginRegistry, choice: const *ViewerPluginChoice)->string
{
    return choicePlugin(registry, choice).displayName()
}

private func createTestPlugin(host: Viewer.Host)
{
    host.attachView(Wnd.create'Wnd(host.contentParent()))
}

private func testPlugin(key = "custom", selector = ".plug")->Viewer.Plugin
{
    var result: retval
    result.key          = key
    result.staticName   = "Custom"
    result.iconAtlas    = viewerIcons()
    result.create       = &createTestPlugin
    result.smokeFixture = "custom.plug"
    result.addSelectors(selector)
    return result
}

// The registry treats every built-in, including basic text, as an ordinary named plugin
// descriptor. Readable bytes do not make an unknown extension a text format.
#test
{
    let textFile   = Gui.Testing.tempFilePath("scope-index-", ".unknown")
    let binaryFile = Gui.Testing.tempFilePath("scope-index-", ".png")
    defer discard catch File.delete(textFile)
    defer discard catch File.delete(binaryFile)
    expect File.writeAllBytes(textFile, "plain UTF-8 text")
    expect File.writeAllBytes(binaryFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    let registry = createViewerPluginRegistry()
    Swag.assert(registry.plugins.count == 15)
    for plugin in registry.plugins do
        Swag.assert(plugin.apiVersion == Viewer.ApiVersion and plugin.create != null and plugin.iconAtlas != null)

    let picture = registry.choices(binaryFile)
    Swag.assert(picture.count == 3)
    Swag.assert(choiceName(&registry, &picture[0]) == "Image")
    Swag.assert(choiceName(&registry, &picture[1]) == "Binary")
    Swag.assert(choiceName(&registry, &picture[2]) == "Hexadecimal")

    let unknown = registry.choices(textFile)
    Swag.assert(unknown.count == 2)
    Swag.assert(choiceName(&registry, &unknown[0]) == "Binary")
    Swag.assert(choiceName(&registry, &unknown[1]) == "Hexadecimal")
    Swag.assert(registry.explicitlySupports("clip.gif"))
    Swag.assert(!registry.explicitlySupports("clip.bin"))
}

// Every descriptor carries one immutable smoke basename, and that file discovers the descriptor
// through the same generic selector and probe phases used by the application.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        Swag.assert((Path.fileName(plugin.smokeFixture.toString()) orelse "") == plugin.smokeFixture.toString())
        let fixture = viewerRegistryFixturePath(plugin.smokeFixture.toString())
        Swag.assert(File.exists(fixture))

        var found: bool
        for choice in registry.choices(fixture.toString()) where choice.key == plugin.key
        {
            found = true
            break
        }

        Swag.assert(found)
        for other, j in registry.plugins where j > i do
            Swag.assert(plugin.smokeFixture != other.smokeFixture)
    }
}

#test
{
    let registry = createViewerPluginRegistry()
    Swag.assert(registry.explicitlySupports("Makefile"))
    Swag.assert(registry.explicitlySupports("DOCKERFILE"))
    Swag.assert(registry.explicitlySupports("CMakeLists.txt"))
    Swag.assert(registry.explicitlySupports(".gitignore"))

    let html = registry.choices("page.html")
    Swag.assert(choiceName(&registry, &html[0]) == "HTML" and choiceName(&registry, &html[1]) == "Code")
    Swag.assert(choiceName(&registry, &registry.choices("Makefile")[0]) == "Code")
    Swag.assert(choiceName(&registry, &registry.choices("Dockerfile")[0]) == "Code")
    Swag.assert(choiceName(&registry, &registry.choices("CMakeLists.txt")[0]) == "Code")
    Swag.assert(choiceName(&registry, &registry.choices(".gitignore")[0]) == "Code")

    let tableChoices = registry.choices("data.csv")
    Swag.assert(choiceName(&registry, &tableChoices[0]) == "Table" and tableChoices[1].key == "binary" and tableChoices[2].key == "hex")
    Swag.assert(registry.choices("family.ttf")[0].key == "font")
    Swag.assert(registry.choices("outlines.otf")[0].key == "binary")
    Swag.assert(registry.choices("movie.mp4")[0].key == "video")
    Swag.assert(registry.choices("movie.mkv")[0].key == "video")
    Swag.assert(registry.choices("score.mid")[0].key == "midi")
    Swag.assert(registry.choices("dialogue.srt")[0].key == "subtitle")
    Swag.assert(registry.choices("bundle.zip")[0].key == "archive")

    const SoundFiles: [11] string = ["sound.wav", "sound.flac", "sound.mp3", "sound.aac", "sound.ac3", "sound.eac3", "sound.ec3", "sound.dts", "sound.ogg", "sound.oga", "sound.opus"]
    for file in SoundFiles do
        Swag.assert(registry.choices(file)[0].key == "sound")
}

// The interpreter line claims an extensionless script before wildcard plugins.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-shebang-", "")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "#!/usr/bin/env python3\nprint('hello')\n")

    let registry = createViewerPluginRegistry()
    let choices  = registry.choices(fileName)
    Swag.assert(choices[0].key == "code" and choices[1].key == "binary" and choices[2].key == "hex")
    Swag.assert(codeLanguage(fileName) == .Python)
}

// Stable keys and icon contexts belong to descriptors rather than hard-coded choice variants.
#test
{
    let registry = createViewerPluginRegistry()
    for plugin, i in registry.plugins
    {
        Swag.assert(!plugin.key.isEmpty() and plugin.key == plugin.key.toLower())
        for other, j in registry.plugins where j > i do
            Swag.assert(plugin.key != other.key and plugin.iconIndex != other.iconIndex)
    }

    let movie = registry.choices("movie.mp4")
    Swag.assert(movie[0].key == "video" and cast(ViewerIcons) choicePlugin(&registry, &movie[0]).iconIndex == .Video)
    Swag.assert(movie[1].key == "binary" and cast(ViewerIcons) choicePlugin(&registry, &movie[1]).iconIndex == .Binary)
    Swag.assert(movie[2].key == "hex" and cast(ViewerIcons) choicePlugin(&registry, &movie[2]).iconIndex == .Hex)

    let plain = Gui.Testing.tempFilePath("scope-keys-", ".txt")
    defer discard catch File.delete(plain)
    expect File.writeAllBytes(plain, "plain UTF-8 text")
    let readable = registry.choices(plain)
    Swag.assert(readable[0].key == TextViewerKey)
    Swag.assert(cast(ViewerIcons) choicePlugin(&registry, &readable[0]).iconIndex == .Text)
}

// A descriptor unknown to the built-in registry participates in discovery and creation without
// adding a choice kind, editing the window, or learning any host implementation type.
#test
{
    var registry = createViewerPluginRegistry()
    expect registry.register(testPlugin())
    let choices = registry.choices("sample.plug")
    Swag.assert(choices[0].key == "custom")

    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    var session = openTestViewer(choicePlugin(&registry, &choices[0])[], &host.root, "sample.plug")
    Swag.assert(session.view != null and session.failureReason.isEmpty())

    var duplicate = testPlugin()
    discard catch registry.register(#move duplicate) as duplicateError
    Swag.assert(duplicateError != null)

    var incompatible = testPlugin("future", ".future")
    incompatible.apiVersion = Viewer.ApiVersion + 1
    discard catch registry.register(#move incompatible) as versionError
    Swag.assert(versionError != null)
}

// Folder navigation groups files by explicitly registered plugins, with extension equality only
// when neither file has a named plugin.
#test
{
    let registry = createViewerPluginRegistry()
    Swag.assert(registry.sharesViewer("a.png", "B.JPG"))
    Swag.assert(!registry.sharesViewer("a.png", "b.wav"))
    Swag.assert(registry.sharesViewer("x.foo", "y.FOO"))
    Swag.assert(!registry.sharesViewer("x.foo", "y.bar"))
    Swag.assert(!registry.sharesViewer("a.png", "x.foo"))
}

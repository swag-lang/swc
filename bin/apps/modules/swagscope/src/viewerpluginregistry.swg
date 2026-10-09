using Core, Core.Errors, Gui

// One plugin offered for the current file.
struct ViewerPluginChoice
{
    pluginIndex: u64        // Index in [[ViewerPluginRegistry.plugins]].
    key:         String     // Stable identity copied from the plugin descriptor.
}

// Viewer plugins available to Swag Scope, in selection order.
struct ViewerPluginRegistry
{
    plugins: Array'Viewer.Plugin
}

// The parts of a file name that select a viewer, lowered once: selectors are written in lower case.
private struct NameKey
{
    name:      String
    extension: String
}

private impl NameKey
{
    func from(fileName: string)->NameKey => {String.toLower(Path.fileName(fileName)), String.toLower(Path.extension(fileName))}

    // Reports whether `plugin` claims this name through an extension or an exact name, or, with
    // `wildcard`, through its `*` fallback.
    mtd const selectedBy(plugin: const *Viewer.Plugin, wildcard: bool)->bool
    {
        for selector in plugin.selectors
        {
            var wanted: string
            if wildcard do
                wanted = "*"
            elif selector[][0] == '.' do
                wanted = .extension
            else do
                wanted = .name
            if selector[] == wanted do
                return true
        }

        return false
    }
}

// Reads the beginning of a file, which is what every content probe decides from.
//
// A file that cannot be opened or read yields no bytes rather than an error: not being able to
// look inside says the same thing as looking and recognizing nothing.
private func readProbeHead(fileName: string)->Array'u8
{
    var result: retval
    var stream = catch File.openReadLive(fileName) as openError
    if openError != null do
        return result
    defer stream.close()

    result.resize(Viewer.ProbeHeadSize)
    let count = catch stream.read(result.toSlice()) as readError
    if readError != null do
        result.clear()
    else do
        result.resize(count)
    return result
}

// Creates the complete built-in plugin registry.
//
// Order is the whole content of this list: the first plugin whose selectors name a file is the one
// the reader gets, and the reading probes and the wildcard fallbacks follow in the order written
// here. A format that recognizes itself from its own bytes therefore has to be registered before
// the readers that answer for anything printable. Each descriptor comes from the viewer that
// implements it, so adding a format means adding one line here and nothing else.
func createViewerPluginRegistry()->ViewerPluginRegistry
{
    var result: retval
    expect result.register(Viewers.Html.viewerPlugin())
    expect result.register(Viewers.Code.viewerPlugin())
    expect result.register(Viewers.MarkdownText.viewerPlugin())
    expect result.register(Viewers.Captions.viewerPlugin())
    expect result.register(Viewers.Picture.viewerPlugin())
    expect result.register(Viewers.Film.viewerPlugin())
    expect result.register(Viewers.PdfDocument.viewerPlugin())
    expect result.register(Viewers.InDesign.viewerPlugin())
    expect result.register(Viewers.Sound.viewerPlugin())
    expect result.register(Viewers.Typeface.viewerPlugin())
    expect result.register(Viewers.Midi.viewerPlugin())
    expect result.register(Viewers.Table.viewerPlugin())
    expect result.register(Viewers.OpenDocument.viewerPlugin())
    expect result.register(Viewers.Archive.viewerPlugin())
    expect result.register(Viewers.PlainText.viewerPlugin())
    expect result.register(Viewers.Binary.viewerPlugin())
    expect result.register(Viewers.Hex.viewerPlugin())
    return result
}

impl ViewerPluginRegistry
{
    // Registers one plugin after validating the host-facing contract.
    mtd register(plugin: Viewer.Plugin) fail
    {
        if plugin.apiVersion != Viewer.ApiVersion do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' uses API version %, host needs %", plugin.key, plugin.apiVersion, Viewer.ApiVersion))}
        if plugin.key.isEmpty() do
            fail InvalidFormatError{"viewer plugin key is missing"}
        if plugin.key != plugin.key.toLower() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is not lowercase", plugin.key))}
        if plugin.staticName.isEmpty() and not plugin.resolveName do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no display name", plugin.key))}
        if plugin.iconAtlas == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no icon document", plugin.key))}
        if plugin.create == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no creation callback", plugin.key))}
        if plugin.smokeFixture.isEmpty() or (Path.fileName(plugin.smokeFixture) orelse "") != plugin.smokeFixture.toString() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' needs one smoke-fixture basename", plugin.key))}
        if plugin.selectors.isEmpty() and not plugin.probe do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no selector or content probe", plugin.key))}
        for current in .plugins where current.key == plugin.key do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is already registered", plugin.key))}
        .plugins.add(#move plugin)
    }

    // Prepares every registered plugin for the application that hosts it.
    //
    // A plugin publishes its translations here, before the selector has to name it and long before
    // the reader opens a file it can show.
    mtd attachTo(app: *Application)
    {
        for plugin in .plugins where plugin.attach do
            plugin.attach(app)
    }

    // Returns the plugin that stands for `fileName`, from its name alone.
    //
    // A list of files decorates a row per file, and reading the beginning of a file to decide
    // what it holds costs one open per row. That is invisible on a local disk and thirty
    // milliseconds a file across a network share, where a folder of six hundred films takes
    // twenty seconds of it before anything else in the window moves. A row therefore reads its
    // glyph from the name, which is what names are for; only the file a reader actually opens
    // is worth looking inside.
    mtd const namePlugin(fileName: string, pluginIndex: *u64)->bool
    {
        let key = NameKey.from(fileName)
        for plugin, index in .plugins where key.selectedBy(plugin, wildcard: false)
        {
            pluginIndex[] = index
            return true
        }

        for plugin, index in .plugins where key.selectedBy(plugin, wildcard: true)
        {
            pluginIndex[] = index
            return true
        }

        return false
    }

    // Returns every viewer available for `fileName` in selection order.
    //
    // The name is asked first, then the content, then the fallbacks. Reading the head is what
    // makes an extensionless note, a renamed archive or a Markdown page reach the viewer that can
    // show it, and it costs one open shared by every probe.
    mtd const choices(fileName: string)->Array'ViewerPluginChoice
    {
        var result:  retval
        var matched: Array'bool
        matched.resize(.plugins.count)
        let key = NameKey.from(fileName)

        let head    = readProbeHead(fileName)
        var content = Viewer.ProbeContent{fileName: fileName, head: head.toSlice(), claimedText: true}

        for plugin, index in .plugins where plugin.matchNames and key.selectedBy(plugin, wildcard: false)
        {
            result.add({index, plugin.key})
            matched[index]      = true
            content.claimed     = true
            content.claimedText = content.claimedText and plugin.textual
        }

        for plugin, index in .plugins where not matched[index] and plugin.probe and plugin.probe(content)
        {
            result.add({index, plugin.key})
            matched[index]      = true
            content.claimed     = true
            content.claimedText = content.claimedText and plugin.textual
        }

        for plugin, index in .plugins where not matched[index] and key.selectedBy(plugin, wildcard: true) do
            result.add({index, plugin.key})
        return result
    }

    // Reports whether two files share one explicitly registered viewer, or the same extension
    // when neither has a format-specific viewer.
    mtd const sharesViewer(a, b: string)->bool
    {
        let keyA = NameKey.from(a)
        let keyB = NameKey.from(b)

        var anyA, anyB: bool
        for plugin in .plugins where plugin.matchNames
        {
            let matchA = keyA.selectedBy(plugin, wildcard: false)
            let matchB = keyB.selectedBy(plugin, wildcard: false)
            if matchA and matchB do
                return true
            anyA = anyA or matchA
            anyB = anyB or matchB
        }

        return not anyA and not anyB and keyA.extension == keyB.extension
    }

    // Reports whether `fileName` has an explicitly registered extension or exact name.
    mtd const explicitlySupports(fileName: string)->bool
    {
        let key = NameKey.from(fileName)
        for plugin in .plugins where plugin.matchNames and key.selectedBy(plugin, wildcard: false) do
            return true
        return false
    }
}

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

// Creates the complete built-in plugin registry.
//
// Order is the whole content of this list: the first plugin whose selectors name a file is the one
// the reader gets, and the reading probes and the wildcard fallbacks follow in the order written
// here. Each descriptor comes from the viewer that implements it, so adding a format means adding
// one line here and nothing else.
func createViewerPluginRegistry()->ViewerPluginRegistry
{
    var result: retval
    expect result.register(htmlViewerPlugin())
    expect result.register(codeViewerPlugin())
    expect result.register(markdownViewerPlugin())
    expect result.register(subtitleViewerPlugin())
    expect result.register(imageViewerPlugin())
    expect result.register(videoViewerPlugin())
    expect result.register(pdfViewerPlugin())
    expect result.register(indesignViewerPlugin())
    expect result.register(soundViewerPlugin())
    expect result.register(fontViewerPlugin())
    expect result.register(midiViewerPlugin())
    expect result.register(tableViewerPlugin())
    expect result.register(openDocumentViewerPlugin())
    expect result.register(archiveViewerPlugin())
    expect result.register(textViewerPlugin())
    expect result.register(binaryViewerPlugin())
    expect result.register(hexViewerPlugin())
    return result
}

impl ViewerPluginRegistry
{
    private mtd const matches(plugin: const *Viewer.Plugin, baseName, extension: string, wildcard: bool)->bool
    {
        for supported in plugin.selectors
        {
            if wildcard and supported[] == "*" do
                return true
            if wildcard do
                continue

            let selector = supported[].toString()
            if selector[0] == '.'
            {
                if selector == extension do
                    return true
            }
            elif selector == baseName do
                return true
        }

        return false
    }

    // Registers one plugin after validating the host-facing contract.
    mtd register(plugin: Viewer.Plugin) fail
    {
        if plugin.apiVersion != Viewer.ApiVersion do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' uses API version %, host needs %", plugin.key, plugin.apiVersion, Viewer.ApiVersion).toString())}
        if plugin.key.isEmpty() do
            fail InvalidFormatError{"viewer plugin key is missing"}
        if plugin.key != plugin.key.toLower() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is not lowercase", plugin.key).toString())}
        if plugin.staticName.isEmpty() and !plugin.resolveName do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no display name", plugin.key).toString())}
        if plugin.iconAtlas == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no icon document", plugin.key).toString())}
        if plugin.create == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no creation callback", plugin.key).toString())}
        if plugin.smokeFixture.isEmpty() or (Path.fileName(plugin.smokeFixture.toString()) orelse "") != plugin.smokeFixture.toString() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' needs one smoke-fixture basename", plugin.key).toString())}
        if plugin.selectors.isEmpty() and !plugin.probe do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no selector or content probe", plugin.key).toString())}
        for current in .plugins where current.key == plugin.key do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is already registered", plugin.key).toString())}
        .plugins.add(#move plugin)
    }

    // Prepares every registered plugin for the application that hosts it.
    //
    // A plugin publishes its translations here, before the selector has to name it and long before
    // the reader opens a file it can show.
    mtd attachTo(app: *Application)
    {
        for plugin in .plugins where plugin.attach do
            plugin.attach!(app)
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
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()

        for plugin, index in .plugins where .matches(plugin, baseName.toString(), extension.toString(), wildcard: false)
        {
            pluginIndex[] = index
            return true
        }

        for plugin, index in .plugins where .matches(plugin, baseName.toString(), extension.toString(), wildcard: true)
        {
            pluginIndex[] = index
            return true
        }

        return false
    }

    // Returns every viewer available for `fileName` in selection order.
    mtd const choices(fileName: string)->Array'ViewerPluginChoice
    {
        var result:  retval
        var matched: Array'bool
        matched.resize(.plugins.count)
        var hasNamedMatch: bool
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()

        for plugin, index in .plugins where plugin.matchNames and .matches(plugin, baseName.toString(), extension.toString(), wildcard: false)
        {
            result.add({index, plugin.key})
            matched[index] = true
            hasNamedMatch  = true
        }

        for plugin, index in .plugins where !matched[index] and plugin.probe and plugin.probe!(fileName, hasNamedMatch)
        {
            result.add({index, plugin.key})
            matched[index] = true
        }

        for plugin, index in .plugins where !matched[index] and .matches(plugin, baseName.toString(), extension.toString(), wildcard: true) do
            result.add({index, plugin.key})
        return result
    }

    // Reports whether two files share one explicitly registered viewer, or the same extension
    // when neither has a format-specific viewer.
    mtd const sharesViewer(a, b: string)->bool
    {
        var extensionA = String.from(Path.extension(a) orelse "")
        extensionA = extensionA.toLower()
        var extensionB = String.from(Path.extension(b) orelse "")
        extensionB = extensionB.toLower()
        var baseA = String.from(Path.fileName(a) orelse "")
        baseA = baseA.toLower()
        var baseB = String.from(Path.fileName(b) orelse "")
        baseB = baseB.toLower()

        var anyA, anyB: bool
        for plugin in .plugins where plugin.matchNames
        {
            let matchA = .matches(plugin, baseA.toString(), extensionA.toString(), wildcard: false)
            let matchB = .matches(plugin, baseB.toString(), extensionB.toString(), wildcard: false)
            if matchA and matchB do
                return true
            anyA = anyA or matchA
            anyB = anyB or matchB
        }

        if !anyA and !anyB do
            return extensionA == extensionB
        return false
    }

    // Reports whether `fileName` has an explicitly registered extension or exact name.
    mtd const explicitlySupports(fileName: string)->bool
    {
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()
        for plugin in .plugins where plugin.matchNames
        {
            for supported in plugin.selectors
            {
                let selector = supported[].toString()
                if selector == "*" do
                    continue
                if selector[0] == '.' and selector == extension.toString() do
                    return true
                if selector[0] != '.' and selector == baseName.toString() do
                    return true
            }
        }

        return false
    }
}

using Core, Core.Errors, Gui

// One plugin selected by a set of lowercase filename extensions.
struct ViewerPluginSpec
{
    id:         String          // Stable plugin identifier used to reuse a loaded library.
    library:    String          // Library filename relative to the index directory.
    extensions: Array'String    // Lowercase extensions, or `*` for the fallback plugin.
}

// Lightweight format index read before any plugin library is loaded.
struct ViewerPluginIndex
{
    directory: String                    // Directory containing the index and plugin libraries.
    specs:     Array'ViewerPluginSpec    // Plugin declarations in selection order.
}

impl ViewerPluginIndex
{
    // Parses the line-oriented plugin index.
    //
    // Each non-comment line is `id|library|.ext;.other`; `*` declares a final fallback.
    func parse(text, directory: string)->ViewerPluginIndex fail
    {
        var result: retval
        result.directory = directory

        for rawLine in Tokenize.splitLines(text)
        {
            let line = Latin1.trim(rawLine)
            if !@countof(line) or line[0] == '#' do
                continue

            let fields = Tokenize.split(line, '|'u8, removeEmpty: false)
            if fields.count != 3 do
                fail InvalidFormatError{"plugin index line needs an id, a library, and extensions"}

            var spec: ViewerPluginSpec
            spec.id      = Latin1.trim(fields[0])
            spec.library = Latin1.trim(fields[1])
            if spec.id.isEmpty() or spec.library.isEmpty() do
                fail InvalidFormatError{"plugin index id and library cannot be empty"}

            for rawExtension in Tokenize.split(fields[2], ';'u8)
            {
                var extension = String.from(Latin1.trim(rawExtension))
                extension = extension.toLower()
                if !extension.isEmpty() do
                    spec.extensions.add(#move extension)
            }

            if spec.extensions.isEmpty() do
                fail InvalidFormatError{"plugin index entry needs at least one extension"}
            result.specs.add(#move spec)
        }

        if result.specs.isEmpty() do
            fail InvalidFormatError{"plugin index contains no plugin"}
        return result
    }

    // Loads an index from disk without loading any listed plugin library.
    func load(fileName: string)->ViewerPluginIndex fail
    {
        let content   = try File.readAllText(fileName)
        let directory = Path.directoryName(fileName) orelse "."
        return parse(content.toString(), directory)
    }

    // Finds the plugin selected for `fileName`, preferring an explicit extension over `*`.
    mtd const find(fileName: string)->#null const *ViewerPluginSpec
    {
        var fallback: #null const *ViewerPluginSpec
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()

        for spec in .specs
        {
            for supported in spec.extensions
            {
                if supported[] == "*"
                {
                    fallback = spec
                    continue
                }
                if supported[] == extension do
                    return spec
            }
        }

        return fallback
    }

    // Reports whether `fileName` has an explicitly registered extension.
    mtd const explicitlySupports(fileName: string)->bool
    {
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        for spec in .specs
        {
            for supported in spec.extensions where supported[] != "*" and supported[] == extension do
                return true
        }
        return false
    }
}

// One plugin library already needed by this process.
struct LoadedViewerPlugin
{
    id:      String               // Matching [[ViewerPluginSpec.id]].
    library: NativeLibrary        // Library kept open while plugin-created windows may exist.
    create:  ViewerPluginCreate = undefined   // Borrowed entry point owned by `library`.
    next:    #null *LoadedViewerPlugin         // Next library loaded by this manager.
}

// Loads plugins on first use and keeps them alive for their views.
struct ViewerPluginManager
{
    first: #null *LoadedViewerPlugin
}

impl ViewerPluginManager
{
    mtd opDrop()
    {
        var item = .first
        while item
        {
            let next = item!.next
            Memory.delete(item)
            item = next
        }
        .first = null
    }

    mtd plugin(spec: const *ViewerPluginSpec, directory: string)->*LoadedViewerPlugin fail
    {
        var item = .first
        while item
        {
            if item!.id == spec.id do
                return item!
            item = item!.next
        }

        let fileName = Path.combine(directory, spec.library.toString())
        var library  = try NativeLibrary.load(fileName)
        let symbol   = library.symbol(ViewerPluginCreateSymbol)
        if !symbol do
            fail UnsupportedFormatError{"viewer plugin has no create entry point"}

        let result = Memory.new'LoadedViewerPlugin()
        result.id      = spec.id
        result.library = #move library
        result.create  = cast(ViewerPluginCreate) symbol!
        result.next    = .first
        .first         = result
        return result
    }

    // Creates the view selected for `fileName`, loading its library when first needed.
    mtd createView(contentParent, commandParent: *Wnd, fileName: string, index: const *ViewerPluginIndex, commands: *#null *Wnd)->#null *Wnd fail
    {
        let spec = index.find(fileName)
        if !spec do
            fail UnsupportedFormatError{"no viewer plugin accepts this file"}

        let plugin = try .plugin(spec, index.directory.toString())
        let view   = plugin.create(contentParent, commandParent, fileName, ViewerPluginApiVersion, commands)
        if !view do
            fail UnsupportedFormatError{"viewer plugin does not support this API version"}
        return view!
    }
}

using Core, Core.Errors, Gui

// One viewer plugin associated with a set of lowercase filename extensions.
struct ViewerPluginSpec
{
    id:          String           // Stable plugin identifier used to reuse a loaded library.
    displayName: String           // Name shown in the viewer selector.
    library:     String           // Library filename relative to the index directory.
    extensions:  Array'String     // Lowercase extensions, or `*` for a viewer available to every file.
}

// Selects whether one available viewer is implemented by the host or a plugin.
enum ViewerChoiceKind
{
    BasicText     // Host-owned read-only UTF-8 text view.
    Plugin        // Lazily loaded plugin view.
}

// One viewer offered for the current file.
struct ViewerChoice
{
    kind:      ViewerChoiceKind
    specIndex: u64 = Swag.U64.Max     // Index in [[ViewerPluginIndex.specs]] for a plugin choice.
    name:      String                 // Name shown in the action-bar selector.
}

// Lightweight format index read before any plugin library is loaded.
struct ViewerPluginIndex
{
    directory: String                     // Directory containing the index and plugin libraries.
    specs:     Array'ViewerPluginSpec     // Plugin declarations in selection order.
}

impl ViewerPluginIndex
{
    // Parses the line-oriented plugin index.
    //
    // Each non-comment line is `id|display name|library|.ext;.other`. A three-field legacy line
    // keeps using its id as the display name. `*` makes that viewer available to every file.
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
            if fields.count != 3 and fields.count != 4 do
                fail InvalidFormatError{"plugin index line needs an id, display name, library, and extensions"}

            var spec: ViewerPluginSpec
            spec.id = Latin1.trim(fields[0])
            if fields.count == 4
            {
                spec.displayName = Latin1.trim(fields[1])
                spec.library     = Latin1.trim(fields[2])
            }
            else
            {
                spec.displayName = spec.id
                spec.library     = Latin1.trim(fields[1])
            }

            if spec.id.isEmpty() or spec.displayName.isEmpty() or spec.library.isEmpty() do
                fail InvalidFormatError{"plugin index id, display name, and library cannot be empty"}

            let extensionField = fields[fields.count - 1]
            for rawExtension in Tokenize.split(extensionField, ';'u8)
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

    private mtd const matches(spec: const *ViewerPluginSpec, extension: string, wildcard: bool)->bool
    {
        for supported in spec.extensions
        {
            if wildcard and supported[] == "*" do
                return true
            if !wildcard and supported[] == extension do
                return true
        }

        return false
    }

    // Returns every viewer available for `fileName` in selection order.
    //
    // Format-specific plugins come first, followed by the host's basic text viewer and plugins
    // registered for `*`. This makes the specialized renderer the default without hiding the
    // source or hexadecimal alternatives.
    mtd const choices(fileName: string)->Array'ViewerChoice
    {
        var result: retval
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()

        for spec, index in .specs where .matches(spec, extension.toString(), wildcard: false) do
            result.add(ViewerChoice{.Plugin, index, spec.displayName})

        result.add(ViewerChoice{.BasicText, Swag.U64.Max, "Basic text"})

        for spec, index in .specs where .matches(spec, extension.toString(), wildcard: true) do
            result.add(ViewerChoice{.Plugin, index, spec.displayName})
        return result
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
    id:      String                             // Matching [[ViewerPluginSpec.id]].
    library: NativeLibrary                      // Library kept open while plugin-created windows may exist.
    create:  ViewerPluginCreate = undefined     // Borrowed entry point owned by `library`.
    next:    #null *LoadedViewerPlugin          // Next library loaded by this manager.
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

    // Creates one selected plugin view, loading its library when first needed.
    mtd createView(contentParent, commandParent: *Wnd, fileName: string, spec: const *ViewerPluginSpec, directory: string, commands: *#null *Wnd)->#null *Wnd fail
    {
        let plugin = try .plugin(spec, directory)
        let view   = plugin.create(contentParent, commandParent, fileName, ViewerPluginApiVersion, commands)
        if !view do
            fail UnsupportedFormatError{"viewer plugin does not support this API version"}
        return view!
    }
}

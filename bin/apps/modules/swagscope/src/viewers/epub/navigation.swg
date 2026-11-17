#global internal
#global namespace Viewers.Epub

using Core, Net

// One authored destination in the book's table of contents.
struct NavigationEntry
{
    title:    String
    path:     String
    fragment: String
    level:    u32 = 1
    chapter:  u64 = Swag.U64.Max
}

private const NavigationLimit      = 4096'u64
private const NavigationDepthLimit = 64'u64

// Keeps XML parsing local and bounded; no DTD or entity is ever resolved.
struct Navigation
{
    entries: Array'NavigationEntry
    failure: String
}

impl NavigationEntry
{
    // Resolves a local EPUB URL, including percent-encoded path and fragment components.
    func resolve(basePath, reference: string)->NavigationEntry
    {
        var result: #returntype
        if not reference.count do
            return result

        let hash     = Utf8.indexOf(reference, '#'rune)
        let path     = hash == Swag.U64.Max ? reference : reference[0 until hash]
        let query    = Utf8.indexOf(path, '?'rune)
        let resource = query == Swag.U64.Max ? path : path[0 until query]
        if Utf8.contains(resource, ':'rune) or
           Utf8.startsWith(resource, "/") or
           Utf8.contains(resource, "\\") do
            return result

        let decoded  = catch Url.decodeComponent(resource) { return result; }
        let local    = cast(string, decoded.toSlice())
        if Utf8.contains(local, ':'rune) or
           Utf8.contains(local, "\\") or
           (local.count and local[0] == '/'u8) do
            return result
        result.path = local.count ? Package.resolvePath(Package.parentPath(basePath), local) : String.from(basePath)
        if hash != Swag.U64.Max
        {
            let fragment = catch Url.decodeComponent(reference[hash + 1 to]) { return NavigationEntry{}; }
            if not Utf8.isValid(fragment.toSlice()) do
                return NavigationEntry{}
            result.fragment = cast(string, fragment.toSlice())
        }

        return result
    }
}

private struct NavigationReader
{
    navigation:      Navigation
    stack:           Array'u64
    elements:        Array'String
    basePath:        string
    ncx:             bool
    inNavigation:    bool
    navigationDepth: u64
    depth:           u64
    listDepth:       u32
    labelDepth:      u64
    anchor:          u64 = Swag.U64.Max
}

private impl NavigationReader
{
    mtd add(reference: string, level: u32)->u64 fail
    {
        if .navigation.entries.count >= NavigationLimit do
            fail Errors.UnsupportedFormatError{texts().err_ContentsTooLarge}
        var entry = NavigationEntry.resolve(.basePath, reference)
        entry.level = Math.max(level, 1'u32)
        .navigation.entries.add(#move entry)
        return .navigation.entries.count - 1
    }

    mtd start(token: const *Package.Token) fail
    {
        if .depth >= NavigationDepthLimit do
            fail Errors.UnsupportedFormatError{texts().err_ContentsTooLarge}
        .depth += 1
        .elements.add(token.name)
        if not .inNavigation
        {
            var selected = .ncx and token.isElement("navMap")
            if not .ncx and token.isElement("nav")
            {
                for word in Tokenize.split(token.attribute("epub:type") orelse "", ' 'u8)
                    where word == "toc" do
                    selected = true
            }

            if selected
            {
                .inNavigation    = true
                .navigationDepth = .depth
            }

            return
        }

        if .ncx
        {
            if token.isElement("navPoint")
            {
                let index = try .add("", cast(u32, .stack.count + 1))
                .stack.add(index)
            }
            elif not .stack.isEmpty() and token.isElement("navLabel")
            {
                .labelDepth = .depth
            }
            elif not .stack.isEmpty() and token.isElement("content")
            {
                let target = NavigationEntry.resolve(.basePath, token.attribute("src") orelse "")
                .navigation.entries[.stack.back()].path     = target.path
                .navigation.entries[.stack.back()].fragment = target.fragment
            }
        }
        else
        {
            if token.isElement("ol") or token.isElement("ul")
            {
                .listDepth += 1
            }
            elif token.isElement("a")
            {
                .anchor     = try .add(token.attribute("href") orelse "", .listDepth)
                .labelDepth = .depth
            }
        }
    }

    mtd end(token: const *Package.Token) fail
    {
        if not .depth or .elements.back() != token.name do
            fail Errors.InvalidFormatError{texts().err_ContentsInvalid}
        discard .elements.popBack()
        if .inNavigation
        {
            if .depth == .labelDepth
            {
                .labelDepth = 0
                .anchor     = Swag.U64.Max
            }

            if .ncx and token.isElement("navPoint") and not .stack.isEmpty() do
                discard .stack.popBack()
            if not .ncx and (token.isElement("ol") or token.isElement("ul")) and .listDepth do
                .listDepth -= 1
            if .depth == .navigationDepth do
                .inNavigation = false
        }

        .depth -= 1
    }

    mtd text(text: string) fail
    {
        if not .inNavigation or not .labelDepth do
            return
        let index = .ncx and not .stack.isEmpty() ? .stack.back() : .anchor
        if index == Swag.U64.Max do
            return
        if .navigation.entries[index].title.count + text.count > 4096 do
            fail Errors.UnsupportedFormatError{texts().err_ContentsTooLarge}
        .navigation.entries[index].title += text
    }
}

impl Navigation
{
    // Reads NCX navMap or the EPUB 3 nav marked `toc`, preserving authored nesting and order.
    func parse(source, basePath: string, ncx: bool)->Navigation fail
    {
        var reader = NavigationReader{basePath: basePath, ncx: ncx}
        var scan   = Package.Scanner.create(source)
        scan.allowDocumentType = true
        var token: Package.Token
        while scan.next(&token)
        {
            switch token.kind
            {
            case .Start:
                try reader.start(&token)
                if token.empty do
                    try reader.end(&token)

            case .End:
                try reader.end(&token)

            case .Text:
                try reader.text(token.text)
            }
        }

        if scan.damaged or reader.depth do
            fail Errors.InvalidFormatError{texts().err_ContentsInvalid}
        return #move reader.navigation
    }

    // Discards destinations outside the spine while preserving safe partial navigation.
    mtd bind(chapters: const [..] Chapter)
    {
        for &entry in .entries
        {
            entry.title.trim()
            if entry.title.isEmpty() or entry.path.isEmpty() do
                continue
            for chapter, index in chapters where chapter.path == entry.path
            {
                entry.chapter = index
                break
            }
        }
    }
}

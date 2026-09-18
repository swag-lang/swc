#global public
#global namespace Resources

using Core.Errors

// One embedded resource: a name and its compile-time bytes.
struct EmbeddedResource
{
    public
    {
        name:  String             // Resource name, with `/` separators.
        bytes: const [..] u8?     // Compile-time bytes, owned by the program image.
    }
}

// Resolves a resource name through an ordered chain of providers.
//
// A resource is a run of bytes addressed by a relative name such as `theme/widgets.png`.
// Names always use `/` as separator, whatever the platform. Disk folders are searched
// first, in registration order, so a folder dropped next to the executable overrides
// what a module embeds; embedded bytes come last, which guarantees that a registered
// name always resolves.
//
// ```swag
// var bundle: Resources.Bundle
// bundle.addEmbedded("lang/fr/app.tweak", EmbeddedFrench)
// bundle.addFolder("datas")
// let bytes = try bundle.load("lang/fr/app.tweak")
// ```
struct Bundle
{
    public
    {
        folders:  Array'String               // Disk roots, searched in registration order.
        embedded: Array'EmbeddedResource     // Compile-time fallback bytes, searched last.
    }
}

impl Bundle
{
    // Appends a disk folder to the search chain.
    //
    // The folder does not need to exist yet: a missing folder never matches a name.
    // Folders registered first win over folders registered later, and every folder
    // wins over embedded bytes.
    mtd addFolder(path: string)
    {
        .folders.add(path)
    }

    // Registers compile-time bytes as the fallback provider for `name`.
    //
    // The bundle borrows `bytes` and never frees them; pass a compile-time constant
    // such as the result of `#include`. Registering the same name again replaces the
    // previous bytes, so registration is idempotent.
    mtd addEmbedded(name: string, bytes: const [..] u8)
    {
        for &entry in .embedded where entry.name == name
        {
            entry.bytes = bytes
            return
        }

        .embedded.add({name, bytes})
    }

    // Returns whether `name` resolves through any provider.
    mtd const has(name: string)->bool => .isOverridden(name) or .findEmbedded(name) != null

    // Returns whether a disk folder provides `name`, hiding any embedded fallback.
    //
    // A caller that caches work derived from embedded bytes can use this to know
    // when the cache does not describe what [[Core.Resources.Bundle.load]] would return.
    mtd const isOverridden(name: string)->bool => not .diskPath(name).isEmpty()

    // Loads the bytes of `name` from the first provider that owns it.
    //
    // The returned bytes are always owned by the caller, embedded content included.
    // Fails with [[Core.Errors.FileNotFoundError]] when no provider knows `name`, or
    // with the underlying filesystem error when a disk read goes wrong.
    mtd const load(name: string)->Array'u8 fail
    {
        let path = .diskPath(name)
        if not path.isEmpty() do
            return try File.readAllBytes(path.toString())

        let entry = .findEmbedded(name)
        if entry
        {
            var result: retval
            result.add(entry.bytes)
            return result
        }

        fail FileNotFoundError{fileName: Errors.mkString(name)}
    }

    // Returns the sorted names of every resource starting with `prefix`.
    //
    // The list is the union of what every disk folder and the embedded table provide,
    // without duplicates, so a language picker can discover what is installed with
    // `list("lang/")`. An empty prefix returns every resource. Unreadable folders are
    // skipped rather than reported: a missing optional folder is not an error.
    mtd const list(prefix: string)->Array'String
    {
        var result: retval

        for folder in .folders
        {
            let files = catch Directory.enumerate(folder.toString(), {recurse: true, wantDirectories: false}) as enumErr
            if enumErr != null do
                continue

            for file in files
            {
                let name = relativeResourceName(folder.toString(), file.fullName.toString())
                if not Utf8.startsWith(name.toString(), prefix) do
                    continue
                if not result.contains(name) do
                    result.add(name)
            }
        }

        for entry in .embedded
        {
            if not Utf8.startsWith(entry.name.toString(), prefix) do
                continue
            if not result.contains(entry.name) do
                result.add(entry.name)
        }

        result.sort()
        return result
    }

    // Returns the full disk path of the first folder providing `name`, or an empty
    // string when no folder does.
    private mtd const diskPath(name: string)->String
    {
        for folder in .folders
        {
            let path = Path.combine(folder.toString(), name)
            if File.exists(path.toString()) do
                return path
        }

        return ""
    }

    private mtd const findEmbedded(name: string)->const *EmbeddedResource?
    {
        for &entry in .embedded where entry.name == name do
            return entry
        return null
    }
}

// Converts an absolute enumerated path back to a `/`-separated resource name.
private func relativeResourceName(root: string, fullName: string)->String
{
    var result: retval

    // The enumeration returns `root` verbatim as the path prefix. A root spelled with a
    // trailing separator already ends with it; otherwise one follows it.
    var rel = fullName
    if fullName.count > root.count and Utf8.startsWith(fullName, root)
    {
        rel = fullName[root.count to]
        if Path.isDirectorySeparator(rel[0]) do
            rel = rel[1 to]
    }

    result = rel
    result.replace("\\", "/")
    return result
}

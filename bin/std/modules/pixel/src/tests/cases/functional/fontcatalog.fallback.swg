#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let root = makeTempImagePath("-fallback")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let primaryPath  = Path.combine(root, "a-primary.ttf")
    let symbolsPath  = Path.combine(root, "b-symbols.ttf")
    let primaryBytes = expect makeFallbackTestBytes(false)
    let symbolsBytes = expect makeFallbackTestBytes(true)
    discard expect File.writeAllBytes(primaryPath, primaryBytes.toSlice())
    discard expect File.writeAllBytes(symbolsPath, symbolsBytes.toSlice())

    // Its metadata is valid, but loading its outlines fails. It sorts before the usable faces.
    var invalid = primaryBytes
    let tables  = cast(u32, invalid[4]) << 8 | invalid[5]
    for table in tables
    {
        let offset = 12'u64 + table * 16
        let tag    = cast(u32, invalid[offset]) << 24 | cast(u32, invalid[offset + 1]) << 16 |
                     cast(u32, invalid[offset + 2]) << 8 | invalid[offset + 3]
        if tag == 0x676C7966 or tag == 0x6C6F6361
        {
            for byte in 4 do
                invalid[offset + byte] = 0
        }
    }

    let invalidPath = Path.combine(root, "0-invalid.ttf")
    discard expect File.writeAllBytes(invalidPath, invalid.toSlice())
    var catalog: FontCatalog
    discard expect catalog.addFile(invalidPath)
    discard expect catalog.addFile(primaryPath)
    discard expect catalog.addFile(symbolsPath)
    var cache: FontCatalogFallbackCache
    cache.setCatalog(catalog, ["Missing family", "Segoe UI"])
    catalog.clear()
    for c in [0'rune, '\t'rune, '\n'rune, '\u009F'rune, '\U0010FFFF'rune] do
        Swag.require(cache.find(c, .Regular) == null)
    Swag.require(cache.faces.count == 0)
    let primary = cache.find('A', .Regular)
    Swag.require(primary == (expect TypeFace.load(primaryPath)))
    let symbols = cache.find('\u2192', .Regular)
    Swag.require(symbols == (expect TypeFace.load(symbolsPath)) and symbols != primary)
    Swag.require(cache.find('\u2192', .Regular) == symbols and cache.faces.count == 2)
    Swag.require(cache.find('\u0905', .Regular) == null and cache.faces.count == 3)
    Swag.require(cache.find('\u0905', .Regular) == null and cache.faces.count == 3)
    discard expect catalog.addFile(symbolsPath)
    var noPreferred: Array'string
    cache.setCatalog(catalog, noPreferred.toSlice())
    Swag.require(cache.faces.count == 0 and cache.find('A', .Regular) == symbols)
}

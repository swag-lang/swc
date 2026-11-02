using Core

// Shared file-catalog fallback policy. Native adapters supply only a snapshot and preferred names.
internal struct FontCatalogFallbackCache
{
    catalog:  FontCatalog
    families: Array'String
    faces:    HashTable'(u64, *TypeFace?)
}

impl FontCatalogFallbackCache
{
    mtd setCatalog(catalog: FontCatalog, preferred: const [..] string)
    {
        .catalog = catalog
        .families.clear()
        .faces.clear()
        for name in preferred do
            .families.add(String.from(name))
        for name in .catalog.familyNames() where not .families.contains(name) do
            .families.add(name)
    }

    mtd find(c: rune, style: FontFamilyStyle)->*TypeFace?
    {
        if not isFontFallbackRune(c) do
            return null
        let key = cast(u64, c) * FontFamilyStyle.count + cast(u64, style)
        if let found = .faces.tryFind(key) do
            return found.value
        var result: *TypeFace?
        for family in .families
        {
            result = .findFamily(family.toString(), c, style)
            if result do
                break
        }

        .faces.add(key, result)
        return result
    }

    private mtd findFamily(family: string, c: rune, style: FontFamilyStyle)->*TypeFace?
    {
        let closest = .catalog.findFace(family, style)
        if not closest do
            return null
        var first: *TypeFace?
        catch { first = try closest.load() }
        if first and first.face.hasChar(c) do
            return first

        // A different style in this family may cover a rune missing from its closest face.
        var result: *TypeFace?
        var score = 0xFFFFFFFF'u32
        for &candidate in .catalog.toSlice()
        {
            if candidate == closest or
               Utf8.compare(candidate.metadata.typographicFamilyName.toString(),
                            closest.metadata.typographicFamilyName.toString(),
                            .UnicodeNoCase) != 0 do
                continue
            let candidateScore = fontCatalogStyleScore(candidate, style)
            if candidateScore >= score do
                continue
            let loaded = catch candidate.load() { continue }
            if loaded.face.hasChar(c)
            {
                result = loaded
                score  = candidateScore
            }
        }

        return result
    }
}

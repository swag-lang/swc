using Core, TrueType

// One file-backed face in a [[Pixel.FontCatalog]].
//
// Owns its path and metadata; it does not retain file bytes or a loaded typeface.
public struct FontFileFace
{
    public
    {
        path:      String           // Absolute source path, without resolving symbolic links.
        faceIndex: u32              // Zero-based index within the file or collection.
        metadata:  FaceMetadata     // Owned names and normalized style properties.
    }
}

public impl FontFileFace
{
    // Loads this exact face into Pixel's process-wide typeface cache.
    //
    // The returned pointer remains valid until module shutdown and must not be deleted.
    // Reports file or font errors when the face has not already been cached.
    mtd const load()->*TypeFace fail => try TypeFace.loadAt(.path.toString(), .faceIndex)
}

// An owned snapshot of font-file metadata, independent of native font enumeration.
//
// Add files with [[Pixel.FontCatalog.addFile]], list families with
// [[Pixel.FontCatalog.familyNames]], then select a face with [[Pixel.FontCatalog.findFace]].
// File contents are read only when adding a new path; clear and rebuild to refresh the snapshot.
// Families use the legacy family names exposed by [[TrueType.FaceMetadata]].
//
// ```swag
// var catalog: Pixel.FontCatalog
// discard try catalog.addFile("fonts/family.ttc")
// if let face = catalog.findFace("Example Sans", .Bold)
// {
//     let typeFace = try face.load()
// }
// ```
#[Swag.Opaque]
public struct FontCatalog
{
    private entries: Array'FontFileFace
}

private func compareFontCatalogFaces(a, b: FontFileFace)->s32
{
    let family = Utf8.compare(a.metadata.familyName.toString(), b.metadata.familyName.toString(), .UnicodeNoCase)
    if family != 0 do
        return family
    let spelling = a.metadata.familyName <=> b.metadata.familyName
    if spelling != 0 do
        return spelling
    let path = a.path <=> b.path
    if path != 0 do
        return path
    return a.faceIndex <=> b.faceIndex
}

private func fontCatalogStyleScore(face: const *FontFileFace, style: FontFamilyStyle)->u32
{
    let italic     = (face.metadata.style & .Italic) != 0
    let wantItalic = style == .Italic or style == .BoldItalic
    var weight     = cast(s32, face.metadata.weight)
    if (face.metadata.style & .Bold) != 0 do
        weight = Math.max(weight, 700)
    var desired = 400
    switch style
    {
    case .Bold, .BoldItalic: desired = 700
    case .Light:    desired = 300
    case .SemiBold: desired = 600
    }

    let slant = italic == wantItalic ? 0'u32 : 1000000'u32
    let width = cast(u32, Math.abs(cast(s32, face.metadata.widthClass) - 5))
    return slant + width * 10000 + cast(u32, Math.abs(weight - desired))
}

public impl FontCatalog
{
    // Adds every face of an sfnt font or collection and returns the number added.
    //
    // Uses an absolute path and the target's path equality rules to suppress repeated paths;
    // returns zero for an existing path, without rereading it. Symbolic-link aliases remain
    // distinct. All metadata is parsed before the catalog changes: file or metadata errors
    // leave it intact. Adding a file invalidates previously borrowed face pointers and slices.
    mtd addFile(path: string)->u32 fail
    {
        let absolute = try Path.absolute(path)
        for &entry in .entries where Path.equals(entry.path.toString(), absolute.toString()) do
            return 0

        let bytes = try File.readAllBytes(absolute.toString())
        let count = try Face.countFaces(bytes.toSlice())
        var pending: Array'FontFileFace
        for index in count
        {
            let metadata = try Face.metadataAt(bytes.toSlice(), index)
            pending.add({path: absolute, faceIndex: index, metadata: metadata})
        }

        .entries.add(pending.toSlice())
        .entries.sort(&compareFontCatalogFaces)
        return count
    }

    // Removes all metadata and invalidates previously borrowed face pointers and slices.
    mtd clear() => .entries.clear()

    // Borrows all faces, sorted by family name, path, and collection index.
    //
    // The slice remains valid until this catalog is mutated or destroyed.
    mtd const toSlice()->const [..] FontFileFace => .entries.toSlice()

    // Returns owned family names in Unicode case-insensitive order.
    //
    // Case variants form one family; its bytewise-smallest spelling is returned.
    // Names are not Unicode-normalized, and the returned array outlives the catalog.
    mtd const familyNames()->Array'String
    {
        var result: #returntype
        for &face in .entries
        {
            if not result.isEmpty() and
               Utf8.compare(result.back().toString(), face.metadata.familyName.toString(), .UnicodeNoCase) == 0 do
                continue
            result.add(face.metadata.familyName)
        }

        return result
    }

    // Borrows the closest available face of a family, or returns `null` if it is absent.
    //
    // Matches the family with Unicode simple case folding. Prefers the requested slant, then
    // normal width, then the nearest weight (300 light, 400 regular, 600 semibold, 700 bold).
    // Ties follow the catalog's stable ordering, independently of insertion order. No synthetic
    // style is applied. The pointer remains valid until this catalog is mutated or destroyed.
    mtd const findFace(family: string, style = FontFamilyStyle.Regular)->const *FontFileFace?
    {
        var result: const *FontFileFace?
        var score = 0xFFFFFFFF'u32
        for &face in .entries
        {
            if Utf8.compare(face.metadata.familyName.toString(), family, .UnicodeNoCase) != 0 do
                continue
            let candidate = fontCatalogStyleScore(face, style)
            if candidate < score
            {
                result = face
                score  = candidate
            }
        }

        return result
    }
}

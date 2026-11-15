#global internal
#global namespace Viewers.Package

using Core

// One safe, package-local OOXML relationship. External targets are never published.
struct Relationship
{
    id:   String
    path: String
    kind: String
}

// Borrows an archive for bounded XML and relationship reads during one document load.
struct PartReader
{
    fileName:        string
    archive:         const *Archive.Zip
    invalidMessage:  string
    tooLargeMessage: string
}

impl PartReader
{
    mtd const text(path: string, required = true, limit = 16 * 1024 * 1024'u64)->String fail
    {
        let entry = .archive.tryFindEntry(path)
        if not entry
        {
            if required do
                fail Errors.InvalidFormatError{.invalidMessage}
            return {}
        }

        if entry.uncompressedSize > limit do
            fail Errors.UnsupportedFormatError{.tooLargeMessage}
        let bytes  = try Archive.Zip.loadEntry(.fileName, entry)
        var source = cast(string, bytes.toSlice())
        if source.count >= 3 and source[0] == 0xEF'u8 and source[1] == 0xBB'u8 and source[2] == 0xBF'u8 do
            source = source[3 to]
        var scan  = Scanner.create(source)
        var token:    Token
        var elements: Array'String
        var roots = 0'u32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if elements.isEmpty() do
                    roots += 1
                if not token.empty do
                    elements.add(token.name)
                if elements.count > 128 do
                    fail Errors.UnsupportedFormatError{.tooLargeMessage}
            }
            elif token.kind == .End
            {
                if elements.isEmpty() or elements.back() != token.name do
                    fail Errors.InvalidFormatError{.invalidMessage}
                discard elements.popBack()
            }
            elif elements.isEmpty()
            {
                var outside = token.text
                outside.trim()
                if not outside.isEmpty() do
                    fail Errors.InvalidFormatError{.invalidMessage}
            }
        }

        if scan.damaged or not elements.isEmpty() or roots != 1 do
            fail Errors.InvalidFormatError{.invalidMessage}
        return source
    }

    mtd const relationships(part: string)->Array'Relationship fail
    {
        let directory = parentPath(part)
        let name      = Path.fileName(part) orelse ""
        let path      = Format.toString("%/_rels/%.rels", directory, name)
        let source    = try .text(path, required: false, limit: 1024 * 1024)
        var scan      = Scanner.create(source)
        var token:  Token
        var result: #returntype
        while scan.next(&token)
        {
            if token.kind != .Start or
               not token.isElement("Relationship") or
               token.attribute("TargetMode") == "External" do
                continue
            let id     = token.attribute("Id") orelse ""
            let target = token.attribute("Target") orelse ""
            let kind   = token.attribute("Type") orelse ""
            if not id.count or not target.count or not kind.count do
                fail Errors.InvalidFormatError{.invalidMessage}
            let resolved = resolveRelationshipTarget(directory, target)
            if resolved.isEmpty() do
                fail Errors.InvalidFormatError{.invalidMessage}
            result.add(Relationship{id, resolved, kind})
            if result.count > 4096 do
                fail Errors.UnsupportedFormatError{.tooLargeMessage}
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{.invalidMessage}
        return result
    }
}

func relationshipPath(relationships: const [..] Relationship, kind: string)->String
{
    for relationship in relationships where Utf8.endsWith(relationship.kind, kind) do
        return relationship.path
    return {}
}

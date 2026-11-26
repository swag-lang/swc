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

// One external OOXML relationship with an inert HTTP(S) target.
struct ExternalRelationship
{
    id:     String
    target: String
    kind:   String
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
    mtd const text(path: string, required = true, limit = 16 * 1024 * 1024_u64, allowDocumentType = false)->String fail
    {
        let entry = .archive.tryFindEntry(path)
        if not entry
        {
            if required
            {
                fail Errors.InvalidFormatError{.invalidMessage}
            }

            return {}
        }

        if entry.uncompressedSize > limit
        {
            fail Errors.UnsupportedFormatError{.tooLargeMessage}
        }

        let bytes  = try Archive.Zip.loadEntry(.fileName, entry)
        var source = cast(string, bytes.toSlice())
        if source.count >= 3 and source[0] == 0xEF_u8 and source[1] == 0xBB_u8 and source[2] == 0xBF_u8
        {
            source = source[3 to]
        }

        var scan = Scanner.create(source)
        scan.allowDocumentType = allowDocumentType
        var token:    Token
        var elements: Array!{String}
        var roots = 0_u32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                scan.allowDocumentType = false
                if elements.isEmpty()
                {
                    roots += 1
                }

                if not token.empty
                {
                    elements.add(token.name)
                }

                if elements.count > 128
                {
                    fail Errors.UnsupportedFormatError{.tooLargeMessage}
                }
            }
            else if token.kind == .End
            {
                if elements.isEmpty() or elements.back() != token.name
                {
                    fail Errors.InvalidFormatError{.invalidMessage}
                }

                discard elements.popBack()
            }
            else if elements.isEmpty()
            {
                var outside = token.text
                outside.trim()
                if not outside.isEmpty()
                {
                    fail Errors.InvalidFormatError{.invalidMessage}
                }
            }
        }

        if scan.damaged or not elements.isEmpty() or roots != 1
        {
            fail Errors.InvalidFormatError{.invalidMessage}
        }

        return source
    }

    mtd const relationships(part: string)->Array!{Relationship} fail
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
               token.attribute("TargetMode") == "External"
            {
                continue
            }

            let id     = token.attribute("Id") orelse ""
            let target = token.attribute("Target") orelse ""
            let kind   = token.attribute("Type") orelse ""
            if not id.count or not target.count or not kind.count
            {
                fail Errors.InvalidFormatError{.invalidMessage}
            }

            let resolved = resolveRelationshipTarget(directory, target)
            if resolved.isEmpty()
            {
                fail Errors.InvalidFormatError{.invalidMessage}
            }

            result.add(Relationship{id, resolved, kind})
            if result.count > 4096
            {
                fail Errors.UnsupportedFormatError{.tooLargeMessage}
            }
        }

        if scan.damaged
        {
            fail Errors.InvalidFormatError{.invalidMessage}
        }

        return result
    }

    // Reads external HTTP(S) relationships without resolving them as package paths.
    mtd const externalRelationships(part: string)->Array!{ExternalRelationship} fail
    {
        let directory = parentPath(part)
        let name      = Path.fileName(part) orelse ""
        let path      = Format.toString("%/_rels/%.rels", directory, name)
        if not .archive.tryFindEntry(path)
        {
            return {}
        }

        let source  = try .text(path, limit: 1024 * 1024)
        var scan    = Scanner.create(source)
        var token:  Token
        var result: #returntype
        var ids:    Array!{String}
        var sawRoot = false
        var depth   = 0_u32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("Relationships")
                    {
                        fail Errors.InvalidFormatError{.invalidMessage}
                    }

                    sawRoot = true
                }

                if depth == 1 and token.isElement("Relationship")
                {
                    let id     = token.attribute("Id") orelse ""
                    let target = token.attribute("Target") orelse ""
                    let kind   = token.attribute("Type") orelse ""
                    if not id.count
                    {
                        fail Errors.InvalidFormatError{.invalidMessage}
                    }

                    for seenId in ids where seenId.toString() == id
                    {
                        fail Errors.InvalidFormatError{.invalidMessage}
                    }

                    ids.add(id)
                    if ids.count > 4096
                    {
                        fail Errors.UnsupportedFormatError{.tooLargeMessage}
                    }

                    if token.attribute("TargetMode") == "External"
                    {
                        if not target.count or not kind.count
                        {
                            fail Errors.InvalidFormatError{.invalidMessage}
                        }

                        if safeExternalTarget(target)
                        {
                            result.add(ExternalRelationship{id, target, kind})
                        }
                    }
                }

                if not token.empty
                {
                    depth += 1
                }
            }
            else if token.kind == .End and depth
            {
                depth -= 1
            }
        }

        if scan.damaged or not sawRoot or depth
        {
            fail Errors.InvalidFormatError{.invalidMessage}
        }

        return result
    }
}

private func safeExternalTarget(target: string)->bool
{
    for value in cast(const [..] u8, target)
    {
        if value <= 0x20_u8 or
           value == 0x7F_u8 or
           value == '\\'_u8 or
           value == '<'_u8 or
           value == '>'_u8 or
           value == '"'_u8
        {
            return false
        }
    }

    if Utf8.startsWith(target, "mailto:", .Latin1NoCase)
    {
        return safeMailtoTarget(target)
    }

    var schemeEnd: u64
    if Utf8.startsWith(target, "https://", .Latin1NoCase)
    {
        schemeEnd = 8
    }
    else if Utf8.startsWith(target, "http://", .Latin1NoCase)
    {
        schemeEnd = 7
    }
    else
    {
        return false
    }

    var authorityEnd = schemeEnd
    while authorityEnd < target.count and
          target[authorityEnd] != '/'_u8 and
          target[authorityEnd] != '?'_u8 and
          target[authorityEnd] != '#'_u8
    {
        authorityEnd += 1
    }

    if authorityEnd == schemeEnd
    {
        return false
    }

    for value in cast(const [..] u8, target[schemeEnd until authorityEnd]) where value == '@'_u8
    {
        return false
    }

    return true
}

private func safeMailtoTarget(target: string)->bool
{
    let recipient = target[7 to]
    if recipient.count == 0
    {
        return false
    }

    var at = Swag.U64.Max
    for value, index in cast(const [..] u8, recipient)
    {
        if value == '@'_u8
        {
            if at != Swag.U64.Max
            {
                return false
            }

            at = index
        }
        else if not ((value >= 'a'_u8 and value <= 'z'_u8) or
                     (value >= 'A'_u8 and value <= 'Z'_u8) or
                     (value >= '0'_u8 and value <= '9'_u8) or
                     value == '.'_u8 or
                     value == '_'_u8 or
                     value == '+'_u8 or
                     value == '-'_u8)
        {
            return false
        }
    }

    if at == Swag.U64.Max or at == 0 or at + 1 >= recipient.count
    {
        return false
    }

    let local  = recipient[0 until at]
    let domain = recipient[at + 1 to]
    if local[0] == '.'_u8 or
       local[local.count - 1] == '.'_u8 or
       domain[0] == '.'_u8 or
       domain[domain.count - 1] == '.'_u8 or
       Utf8.contains(recipient, "..")
    {
        return false
    }

    return true
}

func relationshipPath(relationships: const [..] Relationship, kind: string)->String
{
    for relationship in relationships where Utf8.endsWith(relationship.kind, kind)
    {
        return relationship.path
    }

    return {}
}

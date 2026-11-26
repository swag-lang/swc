#global internal
#global namespace Viewers.Package

using Core

// Resolves a package-relative URL to a safe normalized ZIP path, or empty when it escapes the package.
func resolvePath(baseDirectory: string, reference: string)->String
{
    if not reference.count or
       reference[0] == '/'_u8 or
       Utf8.contains(reference, "\\") or
       Utf8.contains(reference, "://")
    {
        return {}
    }

    var parts: Array!{String}
    for part in Tokenize.split(baseDirectory, '/'_rune) where part.count
    {
        parts.add(part)
    }

    var end = 0_u64
    while end < reference.count and reference[end] != '#'_u8 and reference[end] != '?'_u8
    {
        end += 1
    }

    for part in Tokenize.split(reference[0 until end], '/'_rune)
    {
        if not part.count or part == "."
        {
            continue
        }

        if part == ".."
        {
            if parts.isEmpty()
            {
                return {}
            }

            discard parts.popBack()
            continue
        }

        if not Path.isValidFileName(part)
        {
            return {}
        }

        parts.add(part)
    }

    if parts.isEmpty()
    {
        return {}
    }

    var result: String
    for part in parts
    {
        if not result.isEmpty()
        {
            result += '/'_u8
        }

        result += part[]
    }

    return result
}

// Relationship targets may be package-absolute; both forms stay inside the ZIP root.
func resolveRelationshipTarget(baseDirectory: string, target: string)->String
{
    if target.count and target[0] == '/'_u8
    {
        return resolvePath("", target[1 to])
    }

    return resolvePath(baseDirectory, target)
}

// Returns the directory before the last slash in a normalized ZIP path.
func parentPath(path: string)->String
{
    var last = Swag.U64.Max
    for value, index in path where value == '/'_u8
    {
        last = index
    }

    return last == Swag.U64.Max ? String{} : String.from(path[0 until last])
}

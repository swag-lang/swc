#global internal
#global namespace Viewers.Package

using Core

// Resolves a package-relative URL to a safe normalized ZIP path, or empty when it escapes the package.
func resolvePath(baseDirectory: string, reference: string)->String
{
    if not reference.count or reference[0] == '/'u8 or Utf8.contains(reference, "\\") or Utf8.contains(reference, "://") do
        return {}

    var parts: Array'String
    for part in Tokenize.split(baseDirectory, '/'rune) where part.count do
        parts.add(part)

    var end = 0'u64
    while end < reference.count and reference[end] != '#'u8 and reference[end] != '?'u8 do
        end += 1
    for part in Tokenize.split(reference[0 until end], '/'rune)
    {
        if not part.count or part == "." do
            continue
        if part == ".."
        {
            if parts.isEmpty() do
                return {}
            discard parts.popBack()
            continue
        }
        if not Path.isValidFileName(part) do
            return {}
        parts.add(part)
    }

    if parts.isEmpty() do
        return {}
    var result: String
    for part in parts
    {
        if not result.isEmpty() do
            result += '/'u8
        result += part[]
    }
    return result
}

// Relationship targets may be package-absolute; both forms stay inside the ZIP root.
func resolveRelationshipTarget(baseDirectory: string, target: string)->String
{
    if target.count and target[0] == '/'u8 do
        return resolvePath("", target[1 to])
    return resolvePath(baseDirectory, target)
}

// Returns the directory before the last slash in a normalized ZIP path.
func parentPath(path: string)->String
{
    var last = Swag.U64.Max
    for value, index in path where value == '/'u8 do
        last = index
    return last == Swag.U64.Max ? String{} : String.from(path[0 until last])
}

#global public
#global namespace Path

using Swag

// Compile-time lexical policy for the selected target. Filesystem access remains a host concern;
// every operation below is a string algorithm governed by these values.
private const TargetHasWindowsPathSyntax = WINDOWS
private const TargetPathCaseSensitive    = not WINDOWS

const DirectorySeparator    = '/'u8                       // Preferred directory separator.
const AltDirectorySeparator = WINDOWS ? '\\'u8 : 0'u8     // Accepted alternate separator, or zero when none exists.
const VolumeSeparator       = WINDOWS ? ':'u8 : 0'u8      // Volume separator, or zero when paths have no volume prefix.

// Returns whether `c` is the preferred or the alternate directory separator.
#[Inline, ConstExpr]
func isDirectorySeparator(c: u8)->bool => c == DirectorySeparator or AltDirectorySeparator != 0 and c == AltDirectorySeparator

// Returns whether `c` ends the directory part of a path: a directory separator or the volume separator.
#[Inline, ConstExpr]
private func endsDirectoryPart(c: u8)->bool => isDirectorySeparator(c) or VolumeSeparator != 0 and c == VolumeSeparator

// Returns whether `path` is a lexically valid path on the selected target.
func isValidPathName(path: string)->bool
{
    if path.count == 0 do
        return false

    let extendedSyntax = TargetHasWindowsPathSyntax and path.count >= 4 and isDirectorySeparator(path[0]) and isDirectorySeparator(path[1]) and path[2] == '?' and isDirectorySeparator(path[3])
    for c, index in path
    {
        if c == 0 do
            return false
        if not TargetHasWindowsPathSyntax do
            continue
        if c < 32 or c == '"' or c == '<' or c == '>' or c == '|' or c == '*' do
            return false
        if c == '?' and (not extendedSyntax or index != 2) do
            return false
    }

    return true
}

// Returns whether `path` is a lexically valid single file name on the selected target.
func isValidFileName(path: string)->bool
{
    if path.count == 0 do
        return false
    for c in path
    {
        if c == 0 or isDirectorySeparator(c) do
            return false
        if TargetHasWindowsPathSyntax and (c < 32 or c == '"' or c == '<' or c == '>' or c == '|' or c == ':' or c == '*' or c == '?') do
            return false
    }

    return true
}

// Returns the length of the root prefix under the selected target's lexical policy.
func rootLength(path: string)->u32
{
    if path.count == 0 do
        return 0
    if not TargetHasWindowsPathSyntax do
        return isDirectorySeparator(path[0]) ? 1 : 0

    func startsWithOrdinal(source, value: string)->bool
    {
        if source.count < value.count do
            return false
        for i in value.count where value[i] != source[i] do
            return false
        return true
    }

    var index                 = 0'u32
    var volumeSeparatorLength = 2'u32
    var uncRootLength         = 2'u32
    let pathLength            = path.count

    const ExtendedPathPrefix = #raw "\\?\"
    const UncExtendedPathPrefix = #raw "\\?\UNC\"

    let extendedSyntax    = startsWithOrdinal(path, ExtendedPathPrefix)
    let extendedUncSyntax = startsWithOrdinal(path, UncExtendedPathPrefix)
    if extendedSyntax
    {
        if extendedUncSyntax do
            uncRootLength = UncExtendedPathPrefix.count
        else do
            volumeSeparatorLength += ExtendedPathPrefix.count
    }

    if (not extendedSyntax or extendedUncSyntax) and isDirectorySeparator(path[0])
    {
        index = 1
        if extendedUncSyntax or pathLength > 1 and isDirectorySeparator(path[1])
        {
            index = uncRootLength
            var separatorCount = 2
            while index < pathLength
            {
                if isDirectorySeparator(path[index])
                {
                    separatorCount -= 1
                    if not separatorCount
                    {
                        index += 1
                        break
                    }
                }

                index += 1
            }
        }
    }
    elif pathLength >= volumeSeparatorLength and path[volumeSeparatorLength - 1] == VolumeSeparator
    {
        index = volumeSeparatorLength
        if pathLength >= volumeSeparatorLength + 1 and isDirectorySeparator(path[volumeSeparatorLength]) do
            index += 1
    }

    return index
}

// Returns the root prefix of `path`, or null when the path is relative.
#[ConstExpr]
func rootName(path: string?)->string?
{
    if path == null do
        return null
    Swag.assert(isValidPathName(path))

    let length = rootLength(path)
    if not length do
        return null
    return path[until length]
}

// Returns whether `path` starts with a directory separator or a volume prefix such as `C:`.
#[ConstExpr]
func isRooted(path: string?)->bool
{
    if path == null do
        return false
    Swag.assert(isValidPathName(path))

    if path.count >= 1 and isDirectorySeparator(path[0]) do
        return true
    return VolumeSeparator != 0 and path.count >= 2 and path[1] == VolumeSeparator
}

// Returns the directory part of `path`, or null when the path names no directory.
//
// A root such as `/` or `C:/` is not a directory part: `directoryName("/file")` is null.
#[ConstExpr]
func directoryName(path: string?)->string?
{
    if path == null do
        return null
    Swag.assert(isValidPathName(path))

    for index in reversed(path.count) where isDirectorySeparator(path[index])
    {
        if index == 0 do
            return null
        if VolumeSeparator != 0 and index == 2 and path[1] == VolumeSeparator do
            return null
        return path[until index]
    }

    return null
}

// Returns the file name part of `path`, or null when the path ends with a separator.
#[ConstExpr]
func fileName(path: string?)->string?
{
    if path == null do
        return null
    Swag.assert(isValidPathName(path))

    for index in reversed(path.count) where endsDirectoryPart(path[index])
    {
        if index == path.count - 1 do
            return null
        return path[index + 1 to]
    }

    return path
}

// Returns the file name part of `path` without its extension, or null when the path ends with a separator.
#[ConstExpr]
func fileNameWithoutExtension(path: string?)->string?
{
    if path == null do
        return null
    Swag.assert(isValidPathName(path))

    var extensionStart = path.count
    for index in reversed(path.count)
    {
        let c = path[index]
        if c == '.' and extensionStart == path.count do
            extensionStart = index
        elif endsDirectoryPart(c)
        {
            if index == path.count - 1 do
                return null
            return path[index + 1 until extensionStart]
        }
    }

    return path[until extensionStart]
}

// Returns the extension of the file name part of `path`, including its '.' character.
//
// Returns null when the file name has no extension.
#[ConstExpr]
func extension(path: string?)->string?
{
    if path == null do
        return null
    Swag.assert(isValidPathName(path))

    for index in reversed(path.count)
    {
        let c = path[index]
        if c == '.' do
            return path[index to]
        if endsDirectoryPart(c) do
            break
    }

    return null
}

// Returns the file name extension in Unicode lowercase, including the '.' character.
//
// Returns an empty string if no extension was found.
func lowercaseExtension(path: string?)->String => String.toLower(extension(path), .Unicode)

// Returns whether the path has `expectedExtension` under the target's case policy.
func hasExtension(path, expectedExtension: string)->bool
{
    if TargetPathCaseSensitive do
        return extension(path) == expectedExtension
    return equals(extension(path) orelse "", expectedExtension)
}

// Returns whether the file name part of `path` has an extension.
#[ConstExpr]
func hasExtension(path: string?)->bool => extension(path) != null

// Joins path segments, inserting a directory separator after a segment that does not end with one.
//
// Null and empty segments are skipped.
func combine(parts: (string?)...)->String
{
    var result: retval
    for one in parts
    {
        let part = one orelse ""
        if part.count == 0 do
            continue

        if not result.isEmpty() and not isDirectorySeparator(result.back()) do
            result += DirectorySeparator

        result += part
    }

    return result
}

// Returns whether two paths are equal under the selected target's case policy.
//
// Case-insensitive targets compare Unicode simple-uppercase values without normalizing paths.
// Malformed UTF-8 is compared byte-for-byte.
func equals(path1, path2: string)->bool
{
    if TargetPathCaseSensitive do
        return path1 == path2
    if path1 == path2 do
        return true

    var offset1, offset2 = 0'u64
    while offset1 < path1.count and offset2 < path2.count
    {
        let first  = Utf8.decodeRune(Swag.makeSlice(path1.buffer + offset1, path1.count - offset1))
        let second = Utf8.decodeRune(Swag.makeSlice(path2.buffer + offset2, path2.count - offset2))
        if first.c == Utf8.RuneError and first.eat == 1 or second.c == Utf8.RuneError and second.eat == 1 do
            return false
        if first.c != second.c and Unicode.toUpper(first.c) != Unicode.toUpper(second.c) do
            return false
        offset1 += first.eat
        offset2 += second.eat
    }

    return offset1 == path1.count and offset2 == path2.count
}

// Replaces the target's alternate separator with its preferred separator.
func normalize(path: *String)
{
    if AltDirectorySeparator do
        path.replace(cast(rune) AltDirectorySeparator, "/")
}

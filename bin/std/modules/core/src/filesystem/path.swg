#global public
#global namespace Path

using Swag

// Compile-time lexical policy for the selected target. Filesystem access remains a host concern;
// every operation below is a string algorithm governed by these values.
private const TargetHasWindowsPathSyntax = WINDOWS
private const TargetPathCaseSensitive = !WINDOWS

const DirectorySeparator    = '/'u8                       // Preferred directory separator.
const AltDirectorySeparator = WINDOWS ? '\\'u8 : 0'u8     // Accepted alternate separator, or zero when none exists.
const VolumeSeparator       = WINDOWS ? ':'u8 : 0'u8      // Volume separator, or zero when paths have no volume prefix.

// Returns true if the given character is a directory separator
#[Inline, ConstExpr]
func isDirectorySeparator(c: u8)->bool
{
    return c == DirectorySeparator or AltDirectorySeparator != 0 and c == AltDirectorySeparator
}

// Returns whether `fullname` is a lexically valid path on the selected target.
func isValidPathName(fullname: string)->bool
{
    if @countof(fullname) == 0 do
        return false

    let extendedSyntax = TargetHasWindowsPathSyntax and @countof(fullname) >= 4 and isDirectorySeparator(fullname[0]) and isDirectorySeparator(fullname[1]) and fullname[2] == '?' and isDirectorySeparator(fullname[3])
    for c, index in fullname
    {
        if c == 0 do
            return false
        if !TargetHasWindowsPathSyntax do
            continue
        if c < 32 or c == '"' or c == '<' or c == '>' or c == '|' or c == '*' do
            return false
        if c == '?' and (!extendedSyntax or index != 2) do
            return false
    }

    return true
}

// Returns whether `fullname` is a lexically valid single file name on the selected target.
func isValidFileName(fullname: string)->bool
{
    if @countof(fullname) == 0 do
        return false
    for c in fullname
    {
        if c == 0 or isDirectorySeparator(c) do
            return false
        if TargetHasWindowsPathSyntax and (c < 32 or c == '"' or c == '<' or c == '>' or c == '|' or c == ':' or c == '*' or c == '?') do
            return false
    }

    return true
}

// Returns the length of the root prefix under the selected target's lexical policy.
func rootLength(fullname: string)->u32
{
    if @countof(fullname) == 0 do
        return 0
    if !TargetHasWindowsPathSyntax do
        return isDirectorySeparator(fullname[0]) ? 1 : 0

    func startsWithOrdinal(source, value: string)->bool
    {
        if @countof(source) < @countof(value) do
            return false
        for i in @countof(value) where value[i] != source[i] do
            return false
        return true
    }

    var index                 = 0'u32
    var volumeSeparatorLength = 2'u32
    var uncRootLength         = 2'u32
    let pathLength            = @countof(fullname)

    const ExtendedPathPrefix = #raw "\\?\"
    const UncExtendedPathPrefix = #raw "\\?\UNC\"

    let extendedSyntax    = startsWithOrdinal(fullname, ExtendedPathPrefix)
    let extendedUncSyntax = startsWithOrdinal(fullname, UncExtendedPathPrefix)
    if extendedSyntax
    {
        if extendedUncSyntax do
            uncRootLength = @countof(UncExtendedPathPrefix)
        else do
            volumeSeparatorLength += @countof(ExtendedPathPrefix)
    }

    if (!extendedSyntax or extendedUncSyntax) and isDirectorySeparator(fullname[0])
    {
        index = 1
        if extendedUncSyntax or pathLength > 1 and isDirectorySeparator(fullname[1])
        {
            index = uncRootLength
            var separatorCount = 2
            while index < pathLength
            {
                if isDirectorySeparator(fullname[index])
                {
                    separatorCount -= 1
                    if !separatorCount
                    {
                        index += 1
                        break
                    }
                }

                index += 1
            }
        }
    }
    elif pathLength >= volumeSeparatorLength and fullname[volumeSeparatorLength - 1] == VolumeSeparator
    {
        index = volumeSeparatorLength
        if pathLength >= volumeSeparatorLength + 1 and isDirectorySeparator(fullname[volumeSeparatorLength]) do
            index += 1
    }

    return index
}

// Returns the root part of the path, null if not found
#[ConstExpr]
func rootName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname
    Debug.assert(isValidPathName(path))
    let length = rootLength(path)
    if !length do
        return null
    return cast() @mkslice(@dataof(path), cast(u64) length)
}

// Returns true if the given path is rooted (starts with a separator or a drive letter and colon)
#[ConstExpr]
func isRooted(fullname: #null string)->bool
{
    if fullname == null do
        return false
    let path = fullname
    Debug.assert(isValidPathName(path))
    let countof = @countof(path)
    if countof >= 1 and isDirectorySeparator(path[0]) do
        return true
    if VolumeSeparator != 0 and countof >= 2 and path[1] == VolumeSeparator do
        return true
    return false
}

// Returns the directory part of the path, null if not found
#[ConstExpr]
func directoryName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname
    Debug.assert(isValidPathName(path))

    let countof = @countof(path)
    var cpt     = countof
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if isDirectorySeparator(c)
        {
            if cpt == 0 do
                return null
            if VolumeSeparator != 0 and cpt == 2 and path[1] == VolumeSeparator do
                return null
            return cast() @mkslice(@dataof(path), cast(u64) cpt)
        }
    }

    return null
}

// Returns the file name part of the path, null if not found
#[ConstExpr]
func fileName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname
    Debug.assert(isValidPathName(path))

    let countof = @countof(path)
    var cpt     = countof
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if isDirectorySeparator(c) or VolumeSeparator != 0 and c == VolumeSeparator
        {
            if cpt == countof - 1 do
                return null
            return cast() @mkslice(@dataof(path) + cpt + 1, cast(u64) (countof - cpt) - 1)
        }
    }

    return path
}

// Returns the file name without its extension, null if not found
#[ConstExpr]
func fileNameWithoutExtension(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname
    Debug.assert(isValidPathName(path))

    let countof = @countof(path)
    var cpt     = countof
    var last    = countof
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if c == '.' and last == countof do
            last = cpt
        elif isDirectorySeparator(c) or VolumeSeparator != 0 and c == VolumeSeparator
        {
            if cpt == countof - 1 do
                return null
            return cast() @mkslice(@dataof(path) + cpt + 1, cast(u64) (last - cpt) - 1)
        }
    }

    if last != countof do
        return cast() @mkslice(@dataof(path), cast(u64) last)
    return path
}

// Returns the file name extension, including the '.' character
// Returns null if no extension was found
#[ConstExpr]
func extension(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname
    Debug.assert(isValidPathName(path))

    var cpt = @countof(path)
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if c == '.' do
            return cast() @mkslice(@dataof(path) + cpt, cast(u64) @countof(path) - cpt)
        if isDirectorySeparator(c) or VolumeSeparator != 0 and c == VolumeSeparator do
            break
    }

    return null
}

// Returns the file name extension in lower case, including the '.' character
// Returns null if no extension was found
func lowercaseExtension(fullname: #null string)->String
{
    return String.toLower(extension(fullname))
}

// Returns whether the path has `expectedExtension` under the target's case policy.
func hasExtension(fullname, expectedExtension: string)->bool
{
    if TargetPathCaseSensitive do
        return extension(fullname) == expectedExtension
    return lowercaseExtension(fullname) == String.toLower(expectedExtension)
}

// Returns true if the file name contains an extension
#[ConstExpr]
func hasExtension(fullname: #null string)->bool
{
    if fullname == null do
        return false
    let path = fullname
    Debug.assert(isValidPathName(path))

    var cpt = @countof(path)
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if c == '.' do
            return true
        if isDirectorySeparator(c) or VolumeSeparator != 0 and c == VolumeSeparator do
            break
    }

    return false
}

// Combines multiple path segments into one, adding a directory separator between them if necessary
func combine(fullnames: #null string...)->String
{
    var result: retval
    for one in fullnames
    {
        let part = one orelse ""
        if @countof(part) == 0 do
            continue

        if result.length
        {
            let c = result.back()
            if !isDirectorySeparator(c) do
                result += DirectorySeparator
        }

        result += part
    }

    return result
}

// Returns whether two paths are equal under the selected target's case policy.
func equals(path1, path2: string)->bool
{
    if TargetPathCaseSensitive do
        return path1 == path2
    return Utf8.compare(path1, path2, .Latin1NoCase) == 0
}

// Replaces the target's alternate separator with its preferred separator.
func normalize(fullname: *String)
{
    if AltDirectorySeparator do
        fullname.replace(cast(rune) AltDirectorySeparator, "/")
}

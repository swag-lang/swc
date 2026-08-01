#global public
#global namespace Path

using Swag

const DirectorySeparator    = '/'u8      // Preferred directory separator.
const AltDirectorySeparator = '\\'u8     // Accepted alternate directory separator.
const VolumeSeparator       = ':'u8      // Volume separator, as in `C:`.

// Returns true if the given character is a directory separator
#[Inline, ConstExpr]
func isDirectorySeparator(c: u8)->bool
{
    return c == DirectorySeparator or c == AltDirectorySeparator
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
    if countof >= 2 and path[1] == VolumeSeparator do
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
            if cpt == 2 and path[1] == VolumeSeparator do
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
        if isDirectorySeparator(c) or c == VolumeSeparator
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
        elif isDirectorySeparator(c) or c == VolumeSeparator
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
        if isDirectorySeparator(c) or c == VolumeSeparator do
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

// Returns true if the given file has the specified extension (case-insensitive)
func hasExtension(fullname, expectedExtension: string)->bool
{
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
        if isDirectorySeparator(c) or c == VolumeSeparator do
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

// Returns true if the two paths are equal (case-insensitive Latin1 comparison)
func equals(path1, path2: string)->bool
{
    return Utf8.compare(path1, path2, .Latin1NoCase) == 0
}

// Normalizes the path by replacing '\' with '/' to conform to standard path format
func normalize(fullname: *String)
{
    fullname.replace("\\", "/")
}

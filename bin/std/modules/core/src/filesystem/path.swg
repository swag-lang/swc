#global public
#global namespace Path
using Swag

const DirectorySeparatorChar    = '/''u8      // Default directory separator character
const AltDirectorySeparatorChar = '\\''u8     // Alternate directory separator character
const VolumeSeparatorChar       = ':''u8      // Volume separator character (e.g., 'C:')

// Returns true if the given character is a directory separator
#[Inline, ConstExpr]
func isDirectorySeparator(c: u8)->bool
{
    return c == DirectorySeparatorChar or c == AltDirectorySeparatorChar
}

// Returns the root part of the path, null if not found
#[ConstExpr]
func getRootName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname orelse ""
    Debug.assert(isValidPathName(path))
    let rootLength = getRootLength(path)
    if !rootLength do
        return null
    return cast() @mkslice(@dataof(path), cast(u64) rootLength)
}

// Returns true if the given path is rooted (starts with a separator or a drive letter and colon)
#[ConstExpr]
func isRooted(fullname: #null string)->bool
{
    if fullname == null do
        return false
    let path = fullname orelse ""
    Debug.assert(isValidPathName(path))
    let countof = @countof(path)
    if countof >= 1 and isDirectorySeparator(path[0]) do
        return true
    if countof >= 2 and path[1] == VolumeSeparatorChar do
        return true
    return false
}

// Returns the directory part of the path, null if not found
#[ConstExpr]
func getDirectoryName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname orelse ""
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
            if cpt == 2 and path[1] == VolumeSeparatorChar do
                return null
            return cast() @mkslice(@dataof(path), cast(u64) cpt)
        }
    }

    return null
}

// Returns the file name part of the path, null if not found
#[ConstExpr]
func getFileName(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname orelse ""
    Debug.assert(isValidPathName(path))

    let countof = @countof(path)
    var cpt     = countof
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if isDirectorySeparator(c) or c == VolumeSeparatorChar
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
func getFileNameWithoutExtension(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname orelse ""
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
        elif isDirectorySeparator(c) or c == VolumeSeparatorChar
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
func getExtension(fullname: #null string)->#null string
{
    if fullname == null do
        return null
    let path = fullname orelse ""
    Debug.assert(isValidPathName(path))

    var cpt = @countof(path)
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if c == '.' do
            return cast() @mkslice(@dataof(path) + cpt, cast(u64) @countof(path) - cpt)
        if isDirectorySeparator(c) or c == VolumeSeparatorChar do
            break
    }

    return null
}

// Returns the file name extension in lower case, including the '.' character
// Returns null if no extension was found
func getExtensionLowerCase(fullname: #null string)->String
{
    return String.toLower(getExtension(fullname))
}

// Returns true if the given file has the specified extension (case-insensitive)
func isExtension(fullname, extension: #nonull string)->bool
{
    return getExtensionLowerCase(fullname) == String.toLower(extension)
}

// Returns true if the file name contains an extension
#[ConstExpr]
func hasExtension(fullname: #null string)->bool
{
    if fullname == null do
        return false
    let path = fullname orelse ""
    Debug.assert(isValidPathName(path))

    var cpt = @countof(path)
    while cpt
    {
        cpt -= 1
        let c = path[cpt]
        if c == '.' do
            return true
        if isDirectorySeparator(c) or c == VolumeSeparatorChar do
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
                result += DirectorySeparatorChar
        }

        result += part
    }

    return result
}

// Returns true if the two paths are equal (case-insensitive Latin1 comparison)
func equals(path1, path2: #nonull string)->bool
{
    return Utf8.compare(path1, path2, .Latin1NoCase) == 0
}

// Normalizes the path by replacing '\' with '/' to conform to standard path format
func normalize(fullname: #nonull *String)
{
    fullname.replace("\\", "/")
}

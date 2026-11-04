#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Path

internal func nativePath(path: string)->String fail
{
    if not isValidPathName(path) do
        fail Errors.InvalidFileNameError{fileName: Errors.mkString(path)}
    return String.from(path)
}

// Returns an absolute path, resolving a relative path against the current directory.
//
// The path need not exist. Dot components and symbolic links are left for the filesystem to
// resolve: removing a `..` after a symbolic link would change which file the path names.
func absolute(path: string)->String fail
{
    let native = try nativePath(path)
    if isRooted(path) do
        return native
    let current = try Directory.currentPath()
    return combine(current, path)
}

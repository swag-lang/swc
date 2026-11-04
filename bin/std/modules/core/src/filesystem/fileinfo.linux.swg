#global if #os == Swag.TargetOs.Linux
#global public
#global namespace File

internal func nativeMetadataAt(directory: s32, name: string)->Linux.Structs.statx fail
{
    let native = try Path.nativePath(name)
    var result: #returntype
    for
    {
        if Linux.statx(directory, native.storage(), Linux.AT_SYMLINK_NOFOLLOW, Linux.STATX_BASIC_STATS | Linux.STATX_BTIME, &result) == 0 do
            return result
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, name)
    }
}

internal func nativeInfoAt(directory: s32, name, fullName: string)->FileInfo fail
{
    let metadata = try nativeMetadataAt(directory, name)
    var result: #returntype
    result.fullName   = fullName
    result.attributes = nativeAttributes(directory, name, metadata)
    result.size       = result.isDirectory() ? 0 : metadata.stx_size
    if metadata.stx_mask & Linux.STATX_BTIME do
        result.creationTime = Time.dateTimeFromUnix(metadata.stx_btime.tv_sec, metadata.stx_btime.tv_nsec)
    if metadata.stx_mask & Linux.STATX_ATIME do
        result.lastAccessTime = Time.dateTimeFromUnix(metadata.stx_atime.tv_sec, metadata.stx_atime.tv_nsec)
    if metadata.stx_mask & Linux.STATX_MTIME do
        result.lastWriteTime = Time.dateTimeFromUnix(metadata.stx_mtime.tv_sec, metadata.stx_mtime.tv_nsec)
    return result
}

// Returns metadata for a file, directory or symbolic link.
//
// A symbolic link reports its own metadata, with Directory set when its target is a resolvable
// directory. Directory size is zero. Times are UTC with millisecond precision; an unavailable
// creation time or a time outside the supported calendar range is a zero DateTime.
func info(fullName: string)->FileInfo fail => try nativeInfoAt(Linux.AT_FDCWD, fullName, fullName)

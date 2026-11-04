#global if #os == Swag.TargetOs.Linux
#global public
#global namespace File

internal func nativeAttributes(directory: s32, name: string, metadata: Linux.Structs.statx)->FileAttributes
{
    var result = FileAttributes.None
    let mode   = cast(u32, metadata.stx_mode)
    let kind   = mode & Linux.S_IFMT
    if metadata.stx_mask & Linux.STATX_MODE and (mode & (Linux.S_IWUSR | Linux.S_IWGRP | Linux.S_IWOTH)) == 0 do
        result |= .ReadOnly
    let leaf = Path.fileName(name) orelse ""
    if leaf.count != 0 and leaf[0] == '.' and leaf != "." and leaf != ".." do
        result |= .Hidden
    if kind == Linux.S_IFDIR do
        result |= .Directory
    if kind == Linux.S_IFBLK or kind == Linux.S_IFCHR do
        result |= .Device
    if kind == Linux.S_IFLNK
    {
        result |= .ReparsePoint

        // A link remains an entry even if its target is missing or inaccessible. Mark a
        // resolvable directory target so directory filters retain it, without recursing into it.
        let native = String.from(name)
        var target: Linux.stat
        for
        {
            if Linux.fstatat(directory, native.storage(), &target, 0) == 0
            {
                if (target.st_mode & Linux.S_IFMT) == Linux.S_IFDIR do
                    result |= .Directory
                break
            }

            if Linux.errno() != Linux.EINTR do
                break
        }
    }

    let attributes = metadata.stx_attributes & metadata.stx_attributes_mask
    if attributes & Linux.STATX_ATTR_COMPRESSED do
        result |= .Compressed
    if attributes & Linux.STATX_ATTR_ENCRYPTED do
        result |= .Encrypted
    return result == .None ? .Normal : result
}

// Returns the Linux characteristics of the named entry, including symbolic links.
//
// Hidden names begin with a dot, except `.` and `..`. ReadOnly means no write permission bit
// is set; it is not an ACL or effective-access check. ReparsePoint identifies a symbolic link,
// and Directory includes links whose directory target can be resolved. Device, Compressed and
// Encrypted reflect native metadata. The remaining flags are not reported on Linux.
func attributes(fullName: string)->FileAttributes fail
{
    let metadata = try nativeMetadataAt(Linux.AT_FDCWD, fullName)
    return nativeAttributes(Linux.AT_FDCWD, fullName, metadata)
}

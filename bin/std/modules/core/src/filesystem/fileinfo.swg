#global public
#global namespace File

using Time

// Metadata returned by [[Core.File.info]] for a file, directory, or symbolic link.
struct FileInfo
{
    public
    {
        fullName:       String               // Path passed to [[Core.File.info]], unchanged
        attributes = FileAttributes.None     // Characteristics such as read-only or hidden
        creationTime:   DateTime             // Creation time in UTC, or zero when unavailable
        lastAccessTime: DateTime             // Last access time, in UTC
        lastWriteTime:  DateTime             // Last modification time, in UTC
        size:           u64                  // Size of the file in bytes, zero for a directory
    }
}

impl FileInfo
{
    // Returns whether the entry is a directory.
    #[Swag.Inline]
    mtd const isDirectory()->bool => .attributes.has(.Directory)
}

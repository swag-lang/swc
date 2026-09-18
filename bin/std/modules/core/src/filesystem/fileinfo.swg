#global public
#global namespace File

using Time

// Describes the metadata of a file or directory.
struct FileInfo
{
    public
    {
        fullName:       String               // Full path of the file or directory
        attributes = FileAttributes.None     // Characteristics such as read-only or hidden
        creationTime:   DateTime             // Creation time, in UTC
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

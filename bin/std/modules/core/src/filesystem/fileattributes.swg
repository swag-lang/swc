#global public
#global namespace File

// Describes the characteristics of a file or directory.
#[Swag.EnumFlags]
enum FileAttributes
{
    None = 0              // No attribute is set
    ReadOnly              // The file cannot be written
    Hidden                // The entry is hidden from ordinary listings
    System                // The entry belongs to the operating system
    Directory             // The entry is a directory
    Archive               // The entry is marked for backup
    Device                // Reserved for system use
    Normal                // The file has no other attribute
    Temporary             // The file holds temporary data
    SparseFile            // The file is sparse
    ReparsePoint          // The entry is a reparse point, such as a symbolic link
    Compressed            // The file is compressed by the file system
    Offline               // The file data is not immediately available
    NotContentIndexed     // The file is excluded from content indexing
    Encrypted             // The file is encrypted by the file system
}

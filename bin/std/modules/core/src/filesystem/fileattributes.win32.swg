#global if WINDOWS
#global public
#global namespace File

using Win32

private impl FileAttributes
{
    func fromDWORD(attributes: DWORD)->FileAttributes
    {
        using FileAttributes
        if attributes == 0xFFFFFFFF
        {
            return None
        }

        var result: FileAttributes = None
        if attributes & FILE_ATTRIBUTE_READONLY
        {
            result |= ReadOnly
        }

        if attributes & FILE_ATTRIBUTE_HIDDEN
        {
            result |= Hidden
        }

        if attributes & FILE_ATTRIBUTE_SYSTEM
        {
            result |= System
        }

        if attributes & FILE_ATTRIBUTE_DIRECTORY
        {
            result |= Directory
        }

        if attributes & FILE_ATTRIBUTE_ARCHIVE
        {
            result |= Archive
        }

        if attributes & FILE_ATTRIBUTE_DEVICE
        {
            result |= Device
        }

        if attributes & FILE_ATTRIBUTE_NORMAL
        {
            result |= Normal
        }

        if attributes & FILE_ATTRIBUTE_TEMPORARY
        {
            result |= Temporary
        }

        if attributes & FILE_ATTRIBUTE_SPARSE_FILE
        {
            result |= SparseFile
        }

        if attributes & FILE_ATTRIBUTE_REPARSE_POINT
        {
            result |= ReparsePoint
        }

        if attributes & FILE_ATTRIBUTE_COMPRESSED
        {
            result |= Compressed
        }

        if attributes & FILE_ATTRIBUTE_OFFLINE
        {
            result |= Offline
        }

        if attributes & FILE_ATTRIBUTE_NOT_CONTENT_INDEXED
        {
            result |= NotContentIndexed
        }

        if attributes & FILE_ATTRIBUTE_ENCRYPTED
        {
            result |= Encrypted
        }

        if attributes & FILE_ATTRIBUTE_INTEGRITY_STREAM
        {
            result |= IntegrityStream
        }

        if attributes & FILE_ATTRIBUTE_NO_SCRUB_DATA
        {
            result |= NoScrubData
        }

        if attributes & FILE_ATTRIBUTE_RECALL_ON_OPEN
        {
            result |= RecallOnOpen
        }

        if attributes & FILE_ATTRIBUTE_PINNED
        {
            result |= Pinned
        }

        if attributes & FILE_ATTRIBUTE_UNPINNED
        {
            result |= Unpinned
        }

        if attributes & FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
        {
            result |= RecallOnDataAccess
        }

        return result
    }
}

// Returns the operating-system attributes of `fullName`.
func attributes(fullName: string)->FileAttributes fail
{
    let winPath    = Utf16.toZeroTerminated(fullName)
    let attributes = catch GetFileAttributesW(winPath.buffer)
    {
        try Errors.transformWinErrors(Swag.err)
        fail Swag.err
    }

    return FileAttributes.fromDWORD(attributes)
}

using Core

namespace SCrypt
{
    enum ErrorKind
    {
        General
        InvalidInput
        NotFound
        AlreadyExists
        AccessDenied
        NotDirectory
        IsDirectory
        DirectoryNotEmpty
        DiskFull
        Corrupted
        Io
    }

    struct Error
    {
        using base: Swag.BaseError
        kind: ErrorKind
    }

    func failWith(message: string, kind = ErrorKind.General) fail
    {
        fail Error{base: {Errors.mkString(message)}, kind: kind}
    }
}


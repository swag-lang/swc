using Core

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
    Canceled
}

struct Error
{
    using base: Swag.BaseError
    kind:       ErrorKind
}

func failWith(message: string, kind = ErrorKind.General) fail
{
    fail Error{base: {Errors.mkString(message)}, kind: kind}
}

#global if #os == Swag.TargetOs.Linux
#global namespace Errors

internal func failLinuxError(error: s32, path: string? = null) fail
{
    let message = mkString(cast(string, cast(cstring, Linux.strerror(error))))
    switch error
    {
    case Linux.ENOENT, Linux.ENOTDIR: fail FileNotFoundError{message, fileName: mkString(path), nativeErrorID: cast(u64, error)}
    case Linux.ENAMETOOLONG: fail InvalidFileNameError{message, fileName: mkString(path), nativeErrorID: cast(u64, error)}
    default: fail Swag.SystemError{message, errorID: cast(u64, error)}
    }
}

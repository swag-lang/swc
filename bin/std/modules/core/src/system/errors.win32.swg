#global if WINDOWS
#global namespace Errors

using Win32

// Fails with the domain error matching a captured Win32 [[Swag.SystemError]], or returns when `err` is null.
//
// The caller captures the error of the failing Win32 call with `catch Win32Call(...) as err`
// and hands it here. A missing file or an invalid name becomes a
// [[Core.Errors.FileNotFoundError]] or a [[Core.Errors.InvalidFileNameError]] naming `val0`;
// any other error is propagated unchanged.
func transformWinErrors(err: any?, val0: string? = null) fail
{
    if err == null do
        return

    let sysErr = cast #assume (const *Swag.SystemError) err
    switch sysErr.errorID
    {
    case ERROR_FILE_NOT_FOUND: fail Errors.FileNotFoundError{fileName: Errors.mkString(val0)}
    case ERROR_INVALID_NAME:   fail Errors.InvalidFileNameError{fileName: Errors.mkString(val0)}
    default: fail err
    }
}

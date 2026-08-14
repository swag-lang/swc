#global if WINDOWS
#global namespace Errors

using Win32

// Translate a captured Win32 SystemError into a domain error. The caller captures the error
// from the failing Win32 call ('catch Win32Call(...) as err') and hands it here; 'err' is null
// when the call succeeded, in which case there is nothing to translate.
func transformWinErrors(err: #null any, val0: #null string = null) fail
{
    if err == null do
        return

    let sysErr = cast(const *Swag.SystemError) err
    switch sysErr.errorID
    {
    case ERROR_FILE_NOT_FOUND: fail Errors.FileNotFoundError{fileName: Errors.mkString(val0)}
    case ERROR_INVALID_NAME:   fail Errors.InvalidFileNameError{fileName: Errors.mkString(val0)}
    default:                   fail err
    }
}

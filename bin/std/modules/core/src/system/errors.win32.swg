#global #if WINDOWS
#global namespace Errors

using Win32

func transformWinErrors(val0: #null string = null) fail
{
    if @err == null do
        return

    let err = cast(const &Swag.SystemError) @err
    switch err.errorID
    {
    case ERROR_FILE_NOT_FOUND: fail Errors.FileNotFoundError{fileName: Errors.mkString(val0)}
    case ERROR_INVALID_NAME:   fail Errors.InvalidFileNameError{fileName: Errors.mkString(val0)}
    default:                   fail @err
    }
}

#global export

// Raises a [[Swag.SystemError]] for an operation that has already reported failure.
//
// The supplied code is preserved, including zero when Windows provides no extended error.
// Callers must test the native failure condition before calling this function. A zero code
// receives a generic failure message instead of the system's success message.
func failWinError(errorMessageID: u32) fail
{
    var err: Swag.SystemError
    err.errorID = errorMessageID
    if errorMessageID == 0
    {
        err.message = "the Windows operation failed without an error code"
        fail err
    }

    let cxt = Swag.getContext()

    // We check that the contextual error allocator has been initialized.
    // In case this is called at a very early stage (in #init)
    if cxt.errorAllocator.capacity
    {
        const MaxLen = 128
        let errorMsg = cast([*] u8) cxt.errorAllocator.alloc(cast() MaxLen)!
        let lang     = cast(DWORD) MAKELANGID(LANG_ENGLISH, SUBLANG_DEFAULT)
        var len      = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorMessageID, lang, cast(LPCSTR) errorMsg, cast(DWORD) MaxLen, null)
        if len
        {
            // Trim right, remove trailing dots, remove trailing non printable characters
            for var idx = len - 1; idx >= 0; idx -= 1
            {
                if errorMsg[idx] > 32 and errorMsg[idx] != '.' do
                    break
                len -= 1
            }

            err.message = Swag.makeString(errorMsg, len)
        }
    }

    fail err
}

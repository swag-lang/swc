#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A checked native sentinel remains a failure even when GetLastError supplies no detail.
#test
{
    catch failWinError(0) as missingCode
    Swag.assert(missingCode is SystemError)
    let missing = cast(SystemError) missingCode
    Swag.assert(missing.errorID == 0)
    Swag.assert(missing.message == "the Windows operation failed without an error code")

    const InvalidHandleError = 6'u32
    catch failWinError(InvalidHandleError) as invalidHandle
    Swag.assert(invalidHandle is SystemError)
    let invalid = cast(SystemError) invalidHandle
    Swag.assert(invalid.errorID == InvalidHandleError)
    Swag.assert(invalid.message != null and invalid.message.count != 0)
}

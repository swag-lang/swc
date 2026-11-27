#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

#test
{
    let handle = expect CreateEventW(null, FALSE, FALSE, null)
    Swag.require(CloseHandle(handle) != FALSE)
}

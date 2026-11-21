#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

#test
{
    const InvalidHandleError = 6'u32
    var errorOutcome: Swag.Error
    discard catch DeleteTimerQueueTimer(null, null, null) as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error is SystemError)
    let systemError = assume cast(*SystemError, error)
    Swag.require(systemError.errorID == InvalidHandleError)
}

#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

#test
{
    var errorOutcome: Swag.Error
    discard catch DeleteTimerQueueTimer(null, null, null) as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error is SystemError)
}

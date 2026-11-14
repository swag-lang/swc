#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Reject dimensions before opening a display connection or allocating image storage.
#test
{
    var rejected: Swag.Error
    discard catch ScreenFrameSource.create(false, 0, 0, 0, 48) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch ScreenFrameSource.create(false, 0, 0, 64, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch ScreenFrameSource.create(true, 0, 0, -2, 48) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// A failed native open must release the owned source exactly once during unwinding.
#static if #os == Swag.TargetOs.Linux
{
    #test
    {
        for 4
        {
            var rejected: Swag.Error
            discard catch ScreenFrameSource.create(false, 0x7FFFFFFF, 0x7FFFFFFF, 1, 1) as rejected
            Swag.require(not rejected.isEmpty())
        }
    }
}

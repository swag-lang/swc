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

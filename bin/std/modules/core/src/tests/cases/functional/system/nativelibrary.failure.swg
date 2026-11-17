#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// An unresolved library path reports failure without leaving an owner behind.
#test
{
    let path = CoreTests.makeFilesystemTestPath(Format.toString("core_missing_library_%", Guid64.random()))
    Swag.require(not File.exists(path.toString()))

    var error: Swag.Error
    discard catch NativeLibrary.load(path.toString()) as error
    Swag.require(error.value() != null)
}

#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let dirName = CoreTests.makeFilesystemTestPath("core_invalid?dir")

    discard catch Directory.create(dirName) as err
    Swag.assert(err != null)
    Swag.assert(err is Errors.InvalidFileNameError)
    Swag.assert(!Directory.exists(dirName))
}

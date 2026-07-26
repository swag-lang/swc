#global #static if #command == Swag.CompilerCommand.Test
#global #static if WINDOWS
#global private

using Swag

#test
{
    let dirName = CoreTests.makeFilesystemTestPath("core_invalid?dir")

    discard catch Directory.create(dirName) as err
    @assert(err != null)
    @assert(err is Errors.InvalidFileNameError)
    @assert(!Directory.exists(dirName))
}

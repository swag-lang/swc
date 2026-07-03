#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global private
using Swag

#test
{
    let dirName = CoreTests.makeFilesystemTestPath("core_invalid?dir")

    discard catch Directory.create(dirName)
    @assert(@err != null)
    @assert(@err is Errors.InvalidFileNameError)
    @assert(!Directory.exists(dirName))
}

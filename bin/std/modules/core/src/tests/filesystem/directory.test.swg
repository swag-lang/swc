#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global fileprivate
using Swag

#test
{
    let dirName: string = "core_invalid?dir"

    discard catch Directory.create(dirName)
    @assert(@err != null)
    @assert(@err is Errors.InvalidFileNameError)
    @assert(!Directory.exists(dirName))
}

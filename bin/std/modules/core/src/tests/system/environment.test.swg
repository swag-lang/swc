#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global fileprivate
using Swag

#test
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    @assert(tempDir.length != 0)
    @assert(Path.isRooted(tempDir.toString()))
    @assert(Directory.exists(tempDir.toString()))
}

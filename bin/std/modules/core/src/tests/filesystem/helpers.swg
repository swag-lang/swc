#global if #command == Swag.CompilerCommand.Test
#global namespace CoreTests

using Swag

func makeFilesystemTestPath(name: string)->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    Swag.assert(not tempDir.isEmpty(), "missing temp directory")

    var fileName: String = "swag_core_"
    fileName += name
    fileName += "_"
    fileName += Guid64.random().toString()
    return Path.combine(tempDir.toString(), fileName.toString())
}

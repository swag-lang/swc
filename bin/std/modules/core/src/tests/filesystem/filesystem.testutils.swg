#global #if #command == Swag.CompilerCommand.Test
#global namespace CoreTests
using Swag

func makeFilesystemTestPath(name: string)->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    Debug.assert(tempDir.length != 0, "missing temp directory")

    var fileName: String = "swag_core_"
    fileName += name
    fileName += "_"
    fileName += GUID64.getRandom().getString()
    return Path.combine(tempDir.toString(), fileName.toString())
}

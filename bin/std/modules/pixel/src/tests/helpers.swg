#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func getTestDataPath(fileName: string, loc = #callerlocation)->string
{
    var path = Path.getDirectoryName(loc.fileName)
    path = Path.combine(path, "data")
    path = Path.combine(path, fileName)
    @assert(File.exists(path))
    return path
}

func makeTempBmpPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_bmp_"
    name += GUID64.getRandom().getString()
    name += ".bmp"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempTgaPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_tga_"
    name += GUID64.getRandom().getString()
    name += ".tga"
    return Path.combine(tempDir.toString(), name.toString())
}

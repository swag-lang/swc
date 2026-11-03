#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#test
{
    let directories = linuxFontDirectories("/home/example", "/home/example/.local/share")
    Swag.assert(directories.count == 4)
    Swag.assert(directories[0] == "/usr/local/share/fonts")
    Swag.assert(directories[1] == "/usr/share/fonts")
    Swag.assert(directories[2] == "/home/example/.local/share/fonts")
    Swag.assert(directories[3] == "/home/example/.fonts")
    let custom = linuxFontDirectories("", "/custom/data")
    Swag.assert(custom.count == 3 and custom[2] == "/custom/data/fonts")
    Swag.assert(linuxFontDirectories("relative", "relative").count == 2)
    Swag.assert(linuxFontDirectories("", "/usr/share").count == 2)
}

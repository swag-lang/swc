#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#test
{
    let directories = linuxFontDirectories("/home/example", "/home/example/.local/share")
    Swag.require(directories.count == 4)
    Swag.require(directories[0] == "/usr/local/share/fonts")
    Swag.require(directories[1] == "/usr/share/fonts")
    Swag.require(directories[2] == "/home/example/.local/share/fonts")
    Swag.require(directories[3] == "/home/example/.fonts")
    let custom = linuxFontDirectories("", "/custom/data")
    Swag.require(custom.count == 3 and custom[2] == "/custom/data/fonts")
    Swag.require(linuxFontDirectories("relative", "relative").count == 2)
    Swag.require(linuxFontDirectories("", "/usr/share").count == 2)
}

#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

#test
{
    let path = "C:\\temp\\file\0suffix"
    Swag.require(not Env.showInFileExplorer(path))
    Swag.require(not Env.openFileWith(path))
    Swag.require(not Env.openFile(path))
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    for url in ["", "file:///tmp/data", "relative/path", "javascript:alert(1)", "https://example.test/a b",
                "https://example.test/\n", "https://example.test/\0"]
    {
        let accepted = Env.openUrl(url)
        Swag.require(not accepted)
    }

    let emptyFile     = Env.openFile("")
    let zeroFile      = Env.openFile("/tmp/value\0suffix")
    let malformed     = [0xFF'u8]
    let malformedFile = Env.openFile(cast(string, malformed))
    Swag.require(not emptyFile and not zeroFile and not malformedFile)
    let emptyReveal     = Env.showInFileExplorer("")
    let zeroReveal      = Env.showInFileExplorer("/tmp/value\0suffix")
    let malformedReveal = Env.showInFileExplorer(cast(string, malformed))
    Swag.require(not emptyReveal and not zeroReveal and not malformedReveal)
}

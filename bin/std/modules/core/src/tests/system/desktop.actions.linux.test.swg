#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    for url in ["", "file:///tmp/data", "relative/path", "javascript:alert(1)", "https://example.test/a b",
                "https://example.test/\n", "https://example.test/\0"]
    {
        let accepted = Env.openUrl(url)
        Swag.assert(not accepted)
    }

    let emptyFile     = Env.openFile("")
    let zeroFile      = Env.openFile("/tmp/value\0suffix")
    let malformed     = [0xFF'u8]
    let malformedFile = Env.openFile(cast(string, malformed))
    Swag.assert(not emptyFile and not zeroFile and not malformedFile)
}

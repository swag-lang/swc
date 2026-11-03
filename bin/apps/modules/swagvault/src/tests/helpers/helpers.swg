#global if #command == Swag.CompilerCommand.Test

using Core

// Fails with a volume error of `kind`, for the tests that check how a failure is reported.
func raiseVolumeError(kind: ErrorKind) fail
{
    fail volumeError(kind)
}
#global internal

// Returns the module's test root for test cases stored under cases/<type>.
func testSourceRoot(loc: Swag.SourceCodeLocation = #callerlocation)->String
{
    var directory = Path.directoryName(loc.fileName)
    while directory != null
    {
        if Path.fileName(directory) == "cases" do
            return unwrap Path.directoryName(directory)
        directory = Path.directoryName(directory)
    }

    Swag.assert(false, "test source is outside cases")
    return ""
}


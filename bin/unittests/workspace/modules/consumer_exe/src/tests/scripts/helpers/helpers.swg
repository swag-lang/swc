#global if #command == Swag.CompilerCommand.Test

#global internal

using Swag, Core

// Returns the module's test root for tests stored under scripts/<type>.
func testSourceRoot(loc: Swag.SourceCodeLocation = #callerlocation)->String
{
    var directory = Path.directoryName(loc.fileName)
    while directory != null
    {
        if Path.fileName(directory) == "scripts" do
            return unwrap Path.directoryName(directory)
        directory = Path.directoryName(directory)
    }

    Swag.assert(false, "test source is outside scripts")
    return ""
}

#global if #command == Swag.CompilerCommand.Test

#global internal

using Swag, Core

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


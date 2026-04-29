#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Path.isDirectorySeparator('/''u8))
    @assert(Path.isDirectorySeparator('\\''u8))
    @assert(!Path.isDirectorySeparator('a''u8))

    @assert(Path.equals(Path.getDirectoryName("src/tests/core.swg") orelse "", "src/tests"))
    @assert(Path.getDirectoryName("core.swg") == null)

    @assert(Path.equals(Path.getFileName("src/tests/core.swg") orelse "", "core.swg"))
    @assert(Path.equals(Path.getFileName("core.swg") orelse "", "core.swg"))

    @assert(Path.equals(Path.getFileNameWithoutExtension("src/tests/core.swg") orelse "", "core"))
    @assert(Path.equals(Path.getFileNameWithoutExtension("core.swg") orelse "", "core"))
    @assert(Path.equals(Path.getFileNameWithoutExtension("core") orelse "", "core"))

    @assert(Path.equals(Path.getExtension("src/tests/core.swg") orelse "", ".swg"))
    @assert(Path.equals(Path.getExtension("core.swg") orelse "", ".swg"))
    @assert(Path.getExtension("core") == null)
    @assert(Path.hasExtension("core.swg"))
    @assert(!Path.hasExtension("core"))

    @assert(Path.combine("src", "tests", "core.swg") == "src/tests/core.swg")
    @assert(Path.equals("SRC/Tests/Core.swg", "src/tests/core.swg"))
}

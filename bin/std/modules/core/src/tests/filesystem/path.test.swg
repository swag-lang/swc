#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Path.isDirectorySeparator('/''u8))
    @assert(Path.isDirectorySeparator('\\''u8))
    @assert(!Path.isDirectorySeparator('a''u8))

    @assert(Path.isValidPathName("src/tests/core.swg"))
    @assert(!Path.isValidPathName(""))
    @assert(!Path.isValidPathName("bad|name"))
    @assert(Path.isValidFileName("core.swg"))
    @assert(!Path.isValidFileName(""))
    @assert(!Path.isValidFileName("src/core.swg"))

    @assert(Path.getRootLength("core.swg") == 0)
    @assert(Path.getRootName("core.swg") == null)
    @assert(!Path.isRooted("core.swg"))
    @assert(Path.getRootLength("/src/core.swg") == 1)
    @assert(Path.equals(Path.getRootName("/src/core.swg") orelse "", "/"))
    @assert(Path.isRooted("/src/core.swg"))
    @assert(Path.getRootLength("C:/src/core.swg") == 3)
    @assert(Path.equals(Path.getRootName("C:/src/core.swg") orelse "", "C:/"))
    @assert(Path.isRooted("C:/src/core.swg"))
    @assert(Path.getRootLength(#"\\server\share\src\core.swg"#) == @countof(#"\\server\share\"#))
    @assert(Path.equals(Path.getRootName(#"\\server\share\src\core.swg"#) orelse "", #"\\server\share\"#))
    @assert(Path.isRooted(#"\\server\share\src\core.swg"#))

    @assert(Path.equals(Path.getDirectoryName("src/tests/core.swg") orelse "", "src/tests"))
    @assert(Path.equals(Path.getDirectoryName("src/tests/") orelse "", "src/tests"))
    @assert(Path.getDirectoryName("core.swg") == null)

    @assert(Path.equals(Path.getFileName("src/tests/core.swg") orelse "", "core.swg"))
    @assert(Path.equals(Path.getFileName("core.swg") orelse "", "core.swg"))
    @assert(Path.getFileName("src/tests/") == null)

    @assert(Path.equals(Path.getFileNameWithoutExtension("src/tests/core.swg") orelse "", "core"))
    @assert(Path.equals(Path.getFileNameWithoutExtension("core.swg") orelse "", "core"))
    @assert(Path.equals(Path.getFileNameWithoutExtension("core") orelse "", "core"))
    @assert(Path.getFileNameWithoutExtension("src/tests/") == null)

    @assert(Path.equals(Path.getExtension("src/tests/core.swg") orelse "", ".swg"))
    @assert(Path.equals(Path.getExtension("core.swg") orelse "", ".swg"))
    @assert(Path.equals(Path.getExtension("archive.tar.gz") orelse "", ".gz"))
    @assert(Path.getExtension("core") == null)
    @assert(Path.getExtension("src.tests/core") == null)
    @assert(Path.hasExtension("core.swg"))
    @assert(Path.hasExtension("archive.tar.gz"))
    @assert(!Path.hasExtension("core"))
    @assert(!Path.hasExtension("src.tests/core"))
    @assert(Path.isExtension("CORE.SWG", ".swg"))

    @assert(Path.combine("src", "tests", "core.swg") == "src/tests/core.swg")
    @assert(Path.combine("", "src/", "tests", "core.swg") == "src/tests/core.swg")
    @assert(Path.equals("SRC/Tests/Core.swg", "src/tests/core.swg"))

    var normalized: String = "src\\tests\\core.swg"
    Path.normalize(&normalized)
    @assert(normalized == "src/tests/core.swg")
}

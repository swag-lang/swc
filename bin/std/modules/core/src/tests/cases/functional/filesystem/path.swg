#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Lexical case-insensitive paths include case pairs outside Latin-1.
#test
{
    if WINDOWS
    {
        Swag.require(Path.equals("C:/\u0100/\u03A3/\u0410.swg", "c:/\u0101/\u03C3/\u0430.SWG"))
        Swag.require(Path.hasExtension("file.\u03A3", ".\u03C3"))
        Swag.require(Path.equals("src/\u03A3.swg", "src/\u03C2.swg"))
        Swag.require(Path.equals("src/\u03C3.swg", "src/\u03C2.swg"))
        Swag.require(Path.equals("src/\u0131.swg", "src/I.swg"))
        Swag.require(Path.hasExtension("file.\u03C2", ".\u03A3"))
        Swag.require(Path.hasExtension("file.\u0131", ".I"))
        Swag.require(Path.equals("src/\u00FF.swg", "src/\u0178.swg"))
        Swag.require(Path.equals("src/\u00B5.swg", "src/\u039C.swg"))
    }
    else
    {
        Swag.require(not Path.equals("/\u0100/\u03A3/\u0410.swg", "/\u0101/\u03C3/\u0430.SWG"))
        Swag.require(not Path.hasExtension("file.\u03A3", ".\u03C3"))
        Swag.require(not Path.equals("src/\u03A3.swg", "src/\u03C2.swg"))
        Swag.require(not Path.equals("src/\u0131.swg", "src/I.swg"))
    }

    Swag.require(not Path.equals("src/\u0130.swg", "src/i.swg"))
    Swag.require(not Path.equals("src/\u00FF.swg", "src/\u00DF.swg"))
    Swag.require(not Path.equals("src/\u00B5.swg", "src/\u0095.swg"))
    Swag.require(not Path.hasExtension("file.\u0130", ".i"))
    Swag.require(Path.lowercaseExtension("file.\u0130") == ".i")

    // String escapes encode code points; construct malformed UTF-8 from raw bytes.
    let invalidBytes: [5] u8 = ['s', 'r', 'c', '/', 0x80]
    let otherBytes:   [5] u8 = ['s', 'r', 'c', '/', 0x81]
    let upperBytes:   [5] u8 = ['S', 'R', 'C', '/', 0x80]
    let invalid              = Swag.makeString(invalidBytes.buffer, invalidBytes.count)
    let other                = Swag.makeString(otherBytes.buffer, otherBytes.count)
    let upper                = Swag.makeString(upperBytes.buffer, upperBytes.count)
    Swag.require(not Path.equals(invalid, other))
    Swag.require(not Path.equals(invalid, "src/\uFFFD"))
    Swag.require(Path.equals(upper, invalid) == WINDOWS)
    Swag.require(Path.equals(invalid, invalid))
    if WINDOWS do
        Swag.require(Path.equals(upper, Swag.makeString(invalidBytes.buffer, invalidBytes.count)))
    Swag.require(Path.equals("src/\uFFFD.swg", "src/\uFFFD.swg"))
    Swag.require(Path.lowercaseExtension("file.\u03A3\u0410") == ".\u03C3\u0430")
    Swag.require(not Path.equals("src/\u00E9.swg", "src/e\u0301.swg"))
    Swag.require(not Path.hasExtension("file.\u03A3", ".\u03B4"))
}

#test
{
    Swag.require(Path.isDirectorySeparator('/'u8))
    Swag.require(Path.isDirectorySeparator('\\'u8))
    Swag.require(not Path.isDirectorySeparator('a'u8))

    Swag.require(Path.isValidPathName("src/tests/core.swg"))
    Swag.require(Path.isValidPathName("C:/src/tests/core.swg"))
    Swag.require(Path.isValidPathName("src:tests/core.swg"))
    Swag.require(not Path.isValidPathName(""))
    Swag.require(not Path.isValidPathName("\x00"))
    Swag.require(not Path.isValidPathName("\x1f"))
    Swag.require(not Path.isValidPathName(#raw """bad"name"""))
    Swag.require(not Path.isValidPathName("bad<name"))
    Swag.require(not Path.isValidPathName("bad>name"))
    Swag.require(not Path.isValidPathName("bad|name"))
    Swag.require(not Path.isValidPathName("bad*name"))
    Swag.require(not Path.isValidPathName("bad?name"))
    if WINDOWS
    {
        Swag.require(not Path.isValidPathName("C:/sandbox/.. /outside.txt"))
        Swag.require(not Path.isValidPathName("C:/sandbox/name. /file.txt"))
        Swag.require(not Path.isValidPathName("C:/sandbox/NUL.txt"))
        Swag.require(not Path.isValidPathName("C:/sandbox/NUL:$DATA"))
        Swag.require(not Path.isValidPathName("C:/sandbox/COM1.log"))
        Swag.require(not Path.isValidPathName("C:/sandbox/com\u00B9.log"))
        Swag.require(not Path.isValidFileName("lPt\u00B2.txt"))
        Swag.require(Path.isValidPathName("C:/sandbox/../outside.txt"))
    }

    Swag.require(Path.isValidFileName("core.swg"))
    Swag.require(Path.isValidFileName(".gitignore"))
    Swag.require(Path.isValidFileName("archive.tar.gz"))
    Swag.require(not Path.isValidFileName("."))
    Swag.require(not Path.isValidFileName(".."))
    Swag.require(not Path.isValidFileName(""))
    Swag.require(not Path.isValidFileName("\x00"))
    Swag.require(not Path.isValidFileName("\x1f"))
    Swag.require(not Path.isValidFileName(#raw """bad"name"""))
    Swag.require(not Path.isValidFileName("bad<name"))
    Swag.require(not Path.isValidFileName("bad>name"))
    Swag.require(not Path.isValidFileName("bad|name"))
    Swag.require(not Path.isValidFileName("bad:name"))
    Swag.require(not Path.isValidFileName("bad*name"))
    Swag.require(not Path.isValidFileName("bad?name"))
    Swag.require(not Path.isValidFileName("src/core.swg"))
    Swag.require(not Path.isValidFileName(#raw "src\core.swg"))
    if WINDOWS
    {
        Swag.require(not Path.isValidFileName("name."))
        Swag.require(not Path.isValidFileName("name "))
        Swag.require(not Path.isValidFileName(".. "))
        Swag.require(not Path.isValidFileName("..."))
        Swag.require(not Path.isValidFileName("NUL"))
        Swag.require(not Path.isValidFileName("nul.txt"))
        Swag.require(not Path.isValidFileName("NUL .txt"))
        Swag.require(not Path.isValidFileName("COM1.log"))
        Swag.require(not Path.isValidFileName("LPT\u00B9"))
    }

    Swag.require(Path.rootLength("core.swg") == 0)
    Swag.require(Path.rootName("core.swg") == null)
    Swag.require(not Path.isRooted("core.swg"))
    Swag.require(Path.rootLength("/src/core.swg") == 1)
    Swag.require(Path.equals(Path.rootName("/src/core.swg") orelse "", "/"))
    Swag.require(Path.isRooted("/src/core.swg"))
    Swag.require(Path.rootLength("C:/src/core.swg") == 3)
    Swag.require(Path.equals(Path.rootName("C:/src/core.swg") orelse "", "C:/"))
    Swag.require(Path.isRooted("C:/src/core.swg"))
    Swag.require(Path.rootLength("C:core.swg") == 2)
    Swag.require(Path.equals(Path.rootName("C:core.swg") orelse "", "C:"))
    Swag.require(Path.isRooted("C:core.swg"))
    Swag.require(Path.rootLength(#raw "\\?\C:\src\core.swg") == (#raw "\\?\C:\").count)
    Swag.require(Path.equals(Path.rootName(#raw "\\?\C:\src\core.swg") orelse "", #raw "\\?\C:\"))
    Swag.require(Path.isRooted(#raw "\\?\C:\src\core.swg"))
    Swag.require(Path.rootLength(#raw "\\server\share\src\core.swg") == (#raw "\\server\share\").count)
    Swag.require(Path.equals(Path.rootName(#raw "\\server\share\src\core.swg") orelse "", #raw "\\server\share\"))
    Swag.require(Path.isRooted(#raw "\\server\share\src\core.swg"))
    Swag.require(Path.rootLength(#raw "\\?\UNC\server\share\src\core.swg") == (#raw "\\?\UNC\server\share\").count)
    Swag.require(Path.equals(Path.rootName(#raw "\\?\UNC\server\share\src\core.swg") orelse "", #raw "\\?\UNC\server\share\"))
    Swag.require(Path.isRooted(#raw "\\?\UNC\server\share\src\core.swg"))

    Swag.require(Path.equals(Path.directoryName("src/tests/core.swg") orelse "", "src/tests"))
    Swag.require(Path.equals(Path.directoryName("src/tests/") orelse "", "src/tests"))
    Swag.require(Path.equals(Path.directoryName("src\\tests\\core.swg") orelse "", "src\\tests"))
    Swag.require(Path.equals(Path.directoryName("C:/src/core.swg") orelse "", "C:/src"))
    Swag.require(Path.equals(Path.directoryName("C:/src/") orelse "", "C:/src"))
    Swag.require(Path.directoryName("core.swg") == null)
    Swag.require(Path.equals(Path.directoryName("/core.swg") orelse "", "/"))
    Swag.require(Path.equals(Path.directoryName("C:/core.swg") orelse "", "C:/"))
    Swag.require(Path.equals(Path.directoryName(#raw "C:\core.swg") orelse "", #raw "C:\"))
    Swag.require(Path.equals(Path.directoryName(#raw "\\server\share\core.swg") orelse "", #raw "\\server\share\"))
    Swag.require(Path.directoryName("/") == null)
    Swag.require(Path.directoryName("C:/") == null)
    Swag.require(Path.directoryName(#raw "\\server\share\") == null)

    Swag.require(Path.equals(Path.fileName("src/tests/core.swg") orelse "", "core.swg"))
    Swag.require(Path.equals(Path.fileName("core.swg") orelse "", "core.swg"))
    Swag.require(Path.equals(Path.fileName("C:/src/core.swg") orelse "", "core.swg"))
    Swag.require(Path.equals(Path.fileName("src\\tests\\core.swg") orelse "", "core.swg"))
    Swag.require(Path.equals(Path.fileName("C:core.swg") orelse "", "core.swg"))
    Swag.require(Path.fileName("src/tests/") == null)
    Swag.require(Path.fileName("C:/src/") == null)

    Swag.require(Path.equals(Path.fileNameWithoutExtension("src/tests/core.swg") orelse "", "core"))
    Swag.require(Path.equals(Path.fileNameWithoutExtension("core.swg") orelse "", "core"))
    Swag.require(Path.equals(Path.fileNameWithoutExtension("archive.tar.gz") orelse "", "archive.tar"))
    Swag.require(Path.equals(Path.fileNameWithoutExtension(".gitignore") orelse "", ""))
    Swag.require(Path.equals(Path.fileNameWithoutExtension("src/.gitignore") orelse "", ""))
    Swag.require(Path.equals(Path.fileNameWithoutExtension("core") orelse "", "core"))
    Swag.require(Path.fileNameWithoutExtension("src/tests/") == null)

    Swag.require(Path.equals(Path.extension("src/tests/core.swg") orelse "", ".swg"))
    Swag.require(Path.equals(Path.extension("core.swg") orelse "", ".swg"))
    Swag.require(Path.equals(Path.extension("archive.tar.gz") orelse "", ".gz"))
    Swag.require(Path.equals(Path.extension(".gitignore") orelse "", ".gitignore"))
    Swag.require(Path.equals(Path.extension("src/.gitignore") orelse "", ".gitignore"))
    #static if not WINDOWS do
        Swag.require(Path.equals(Path.extension("core.") orelse "", "."))
    Swag.require(Path.extension("core") == null)
    Swag.require(Path.extension("src.tests/core") == null)
    Swag.require(Path.hasExtension("core.swg"))
    Swag.require(Path.hasExtension("archive.tar.gz"))
    Swag.require(Path.hasExtension(".gitignore"))
    #static if not WINDOWS do
        Swag.require(Path.hasExtension("core."))
    Swag.require(not Path.hasExtension("core"))
    Swag.require(not Path.hasExtension("src.tests/core"))
    Swag.require(Path.hasExtension("CORE.SWG", ".swg"))
    Swag.require(Path.hasExtension("core.SWG", ".SwG"))
    Swag.require(not Path.hasExtension("core.swg", ".txt"))

    Swag.require(Path.combine("src", "tests", "core.swg") == "src/tests/core.swg")
    Swag.require(Path.combine("", "src/", "tests", "core.swg") == "src/tests/core.swg")
    Swag.require(Path.combine("src", "", "", "core.swg") == "src/core.swg")
    Swag.require(Path.combine("src/", "/core.swg") == "src//core.swg")
    Swag.require(Path.equals("SRC/Tests/Core.swg", "src/tests/core.swg"))
    Swag.require(not Path.equals("SRC/Tests/Core.swg", "src/tests/other.swg"))

    var normalized: String = "src\\tests\\core.swg"
    Path.normalize(&normalized)
    Swag.require(normalized == "src/tests/core.swg")

    normalized = #raw "C:\src\tests\core.swg"
    Path.normalize(&normalized)
    Swag.require(normalized == "C:/src/tests/core.swg")
}

// Distinct UTF-8 directory names must remain distinct under every target case policy.
#test
{
    Swag.require(not Path.equals("C:/\u0100/bin", "C:/\u0120/bin"))
    Swag.require(not Path.equals("C:/\U0001F600/bin", "C:/\U0001F620/bin"))
}

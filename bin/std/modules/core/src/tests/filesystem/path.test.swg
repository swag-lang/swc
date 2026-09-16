#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Lexical case-insensitive paths include case pairs outside Latin-1.
#test
{
    if WINDOWS
    {
        Swag.assert(Path.equals("C:/\u0100/\u03A3/\u0410.swg", "c:/\u0101/\u03C3/\u0430.SWG"))
        Swag.assert(Path.hasExtension("file.\u03A3", ".\u03C3"))
        Swag.assert(Path.equals("src/\u03A3.swg", "src/\u03C2.swg"))
        Swag.assert(Path.equals("src/\u03C3.swg", "src/\u03C2.swg"))
        Swag.assert(Path.equals("src/\u0131.swg", "src/I.swg"))
        Swag.assert(Path.hasExtension("file.\u03C2", ".\u03A3"))
        Swag.assert(Path.hasExtension("file.\u0131", ".I"))
        Swag.assert(Path.equals("src/\u00FF.swg", "src/\u0178.swg"))
        Swag.assert(Path.equals("src/\u00B5.swg", "src/\u039C.swg"))
    }
    else
    {
        Swag.assert(not Path.equals("/\u0100/\u03A3/\u0410.swg", "/\u0101/\u03C3/\u0430.SWG"))
        Swag.assert(not Path.hasExtension("file.\u03A3", ".\u03C3"))
        Swag.assert(not Path.equals("src/\u03A3.swg", "src/\u03C2.swg"))
        Swag.assert(not Path.equals("src/\u0131.swg", "src/I.swg"))
    }

    Swag.assert(not Path.equals("src/\u0130.swg", "src/i.swg"))
    Swag.assert(not Path.equals("src/\u00FF.swg", "src/\u00DF.swg"))
    Swag.assert(not Path.equals("src/\u00B5.swg", "src/\u0095.swg"))
    Swag.assert(not Path.hasExtension("file.\u0130", ".i"))
    Swag.assert(Path.lowercaseExtension("file.\u0130") == ".i")

    // String escapes encode code points; construct malformed UTF-8 from raw bytes.
    let invalidBytes: [5] u8 = ['s', 'r', 'c', '/', 0x80]
    let otherBytes:   [5] u8 = ['s', 'r', 'c', '/', 0x81]
    let upperBytes:   [5] u8 = ['S', 'R', 'C', '/', 0x80]
    let invalid              = Swag.makeString(invalidBytes.buffer, invalidBytes.count)
    let other                = Swag.makeString(otherBytes.buffer, otherBytes.count)
    let upper                = Swag.makeString(upperBytes.buffer, upperBytes.count)
    Swag.assert(not Path.equals(invalid, other))
    Swag.assert(not Path.equals(invalid, "src/\uFFFD"))
    Swag.assert(not Path.equals(upper, invalid))
    Swag.assert(Path.equals(invalid, invalid))
    Swag.assert(Path.equals("src/\uFFFD.swg", "src/\uFFFD.swg"))
    Swag.assert(Path.lowercaseExtension("file.\u03A3\u0410") == ".\u03C3\u0430")
    Swag.assert(not Path.equals("src/\u00E9.swg", "src/e\u0301.swg"))
    Swag.assert(not Path.hasExtension("file.\u03A3", ".\u03B4"))
}

#test
{
    Swag.assert(Path.isDirectorySeparator('/'u8))
    Swag.assert(Path.isDirectorySeparator('\\'u8))
    Swag.assert(not Path.isDirectorySeparator('a'u8))

    Swag.assert(Path.isValidPathName("src/tests/core.swg"))
    Swag.assert(Path.isValidPathName("C:/src/tests/core.swg"))
    Swag.assert(Path.isValidPathName("src:tests/core.swg"))
    Swag.assert(not Path.isValidPathName(""))
    Swag.assert(not Path.isValidPathName("\x00"))
    Swag.assert(not Path.isValidPathName("\x1f"))
    Swag.assert(not Path.isValidPathName(#raw """bad"name"""))
    Swag.assert(not Path.isValidPathName("bad<name"))
    Swag.assert(not Path.isValidPathName("bad>name"))
    Swag.assert(not Path.isValidPathName("bad|name"))
    Swag.assert(not Path.isValidPathName("bad*name"))
    Swag.assert(not Path.isValidPathName("bad?name"))

    Swag.assert(Path.isValidFileName("core.swg"))
    Swag.assert(Path.isValidFileName(".gitignore"))
    Swag.assert(Path.isValidFileName("archive.tar.gz"))
    Swag.assert(not Path.isValidFileName(""))
    Swag.assert(not Path.isValidFileName("\x00"))
    Swag.assert(not Path.isValidFileName("\x1f"))
    Swag.assert(not Path.isValidFileName(#raw """bad"name"""))
    Swag.assert(not Path.isValidFileName("bad<name"))
    Swag.assert(not Path.isValidFileName("bad>name"))
    Swag.assert(not Path.isValidFileName("bad|name"))
    Swag.assert(not Path.isValidFileName("bad:name"))
    Swag.assert(not Path.isValidFileName("bad*name"))
    Swag.assert(not Path.isValidFileName("bad?name"))
    Swag.assert(not Path.isValidFileName("src/core.swg"))
    Swag.assert(not Path.isValidFileName(#raw "src\core.swg"))

    Swag.assert(Path.rootLength("core.swg") == 0)
    Swag.assert(Path.rootName("core.swg") == null)
    Swag.assert(not Path.isRooted("core.swg"))
    Swag.assert(Path.rootLength("/src/core.swg") == 1)
    Swag.assert(Path.equals(Path.rootName("/src/core.swg") orelse "", "/"))
    Swag.assert(Path.isRooted("/src/core.swg"))
    Swag.assert(Path.rootLength("C:/src/core.swg") == 3)
    Swag.assert(Path.equals(Path.rootName("C:/src/core.swg") orelse "", "C:/"))
    Swag.assert(Path.isRooted("C:/src/core.swg"))
    Swag.assert(Path.rootLength("C:core.swg") == 2)
    Swag.assert(Path.equals(Path.rootName("C:core.swg") orelse "", "C:"))
    Swag.assert(Path.isRooted("C:core.swg"))
    Swag.assert(Path.rootLength(#raw "\\?\C:\src\core.swg") == (#raw "\\?\C:\").count)
    Swag.assert(Path.equals(Path.rootName(#raw "\\?\C:\src\core.swg") orelse "", #raw "\\?\C:\"))
    Swag.assert(Path.isRooted(#raw "\\?\C:\src\core.swg"))
    Swag.assert(Path.rootLength(#raw "\\server\share\src\core.swg") == (#raw "\\server\share\").count)
    Swag.assert(Path.equals(Path.rootName(#raw "\\server\share\src\core.swg") orelse "", #raw "\\server\share\"))
    Swag.assert(Path.isRooted(#raw "\\server\share\src\core.swg"))
    Swag.assert(Path.rootLength(#raw "\\?\UNC\server\share\src\core.swg") == (#raw "\\?\UNC\server\share\").count)
    Swag.assert(Path.equals(Path.rootName(#raw "\\?\UNC\server\share\src\core.swg") orelse "", #raw "\\?\UNC\server\share\"))
    Swag.assert(Path.isRooted(#raw "\\?\UNC\server\share\src\core.swg"))

    Swag.assert(Path.equals(Path.directoryName("src/tests/core.swg") orelse "", "src/tests"))
    Swag.assert(Path.equals(Path.directoryName("src/tests/") orelse "", "src/tests"))
    Swag.assert(Path.equals(Path.directoryName("src\\tests\\core.swg") orelse "", "src\\tests"))
    Swag.assert(Path.equals(Path.directoryName("C:/src/core.swg") orelse "", "C:/src"))
    Swag.assert(Path.equals(Path.directoryName("C:/src/") orelse "", "C:/src"))
    Swag.assert(Path.directoryName("core.swg") == null)
    Swag.assert(Path.directoryName("/core.swg") == null)
    Swag.assert(Path.directoryName("C:/core.swg") == null)

    Swag.assert(Path.equals(Path.fileName("src/tests/core.swg") orelse "", "core.swg"))
    Swag.assert(Path.equals(Path.fileName("core.swg") orelse "", "core.swg"))
    Swag.assert(Path.equals(Path.fileName("C:/src/core.swg") orelse "", "core.swg"))
    Swag.assert(Path.equals(Path.fileName("src\\tests\\core.swg") orelse "", "core.swg"))
    Swag.assert(Path.equals(Path.fileName("C:core.swg") orelse "", "core.swg"))
    Swag.assert(Path.fileName("src/tests/") == null)
    Swag.assert(Path.fileName("C:/src/") == null)

    Swag.assert(Path.equals(Path.fileNameWithoutExtension("src/tests/core.swg") orelse "", "core"))
    Swag.assert(Path.equals(Path.fileNameWithoutExtension("core.swg") orelse "", "core"))
    Swag.assert(Path.equals(Path.fileNameWithoutExtension("archive.tar.gz") orelse "", "archive.tar"))
    Swag.assert(Path.equals(Path.fileNameWithoutExtension(".gitignore") orelse "", ""))
    Swag.assert(Path.equals(Path.fileNameWithoutExtension("src/.gitignore") orelse "", ""))
    Swag.assert(Path.equals(Path.fileNameWithoutExtension("core") orelse "", "core"))
    Swag.assert(Path.fileNameWithoutExtension("src/tests/") == null)

    Swag.assert(Path.equals(Path.extension("src/tests/core.swg") orelse "", ".swg"))
    Swag.assert(Path.equals(Path.extension("core.swg") orelse "", ".swg"))
    Swag.assert(Path.equals(Path.extension("archive.tar.gz") orelse "", ".gz"))
    Swag.assert(Path.equals(Path.extension(".gitignore") orelse "", ".gitignore"))
    Swag.assert(Path.equals(Path.extension("src/.gitignore") orelse "", ".gitignore"))
    Swag.assert(Path.equals(Path.extension("core.") orelse "", "."))
    Swag.assert(Path.extension("core") == null)
    Swag.assert(Path.extension("src.tests/core") == null)
    Swag.assert(Path.hasExtension("core.swg"))
    Swag.assert(Path.hasExtension("archive.tar.gz"))
    Swag.assert(Path.hasExtension(".gitignore"))
    Swag.assert(Path.hasExtension("core."))
    Swag.assert(not Path.hasExtension("core"))
    Swag.assert(not Path.hasExtension("src.tests/core"))
    Swag.assert(Path.hasExtension("CORE.SWG", ".swg"))
    Swag.assert(Path.hasExtension("core.SWG", ".SwG"))
    Swag.assert(not Path.hasExtension("core.swg", ".txt"))

    Swag.assert(Path.combine("src", "tests", "core.swg") == "src/tests/core.swg")
    Swag.assert(Path.combine("", "src/", "tests", "core.swg") == "src/tests/core.swg")
    Swag.assert(Path.combine("src", "", "", "core.swg") == "src/core.swg")
    Swag.assert(Path.combine("src/", "/core.swg") == "src//core.swg")
    Swag.assert(Path.equals("SRC/Tests/Core.swg", "src/tests/core.swg"))
    Swag.assert(not Path.equals("SRC/Tests/Core.swg", "src/tests/other.swg"))

    var normalized: String = "src\\tests\\core.swg"
    Path.normalize(&normalized)
    Swag.assert(normalized == "src/tests/core.swg")

    normalized = #raw "C:\src\tests\core.swg"
    Path.normalize(&normalized)
    Swag.assert(normalized == "C:/src/tests/core.swg")
}

// Distinct UTF-8 directory names must remain distinct under every target case policy.
#test
{
    Swag.assert(not Path.equals("C:/\u0100/bin", "C:/\u0120/bin"))
    Swag.assert(not Path.equals("C:/\U0001F600/bin", "C:/\U0001F620/bin"))
}

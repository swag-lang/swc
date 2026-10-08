#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    Swag.assert(not tempDir.isEmpty())
    Swag.assert(Path.isRooted(tempDir.toString()))
    Swag.assert(Directory.exists(tempDir.toString()))
}

// A '#test' is a program run, whether it executes in the JIT pass of 'swc test' or in the
// generated executable, so both must expose the same command line. The test command always
// injects the 'swag.test' run argument, which makes it the one argument every run is guaranteed
// to see: if 'Swag.args()' comes back empty here, run arguments are not reaching this pass at all and
// nothing can be driven from the command line.
#test
{
    Swag.assert(Env.arguments().count != 0)
    Swag.assert(Env.hasArgument("swag.test"))
    Swag.assert(Env.executablePath().count != 0)
}

// Only absolute web addresses reach the system handler; a document link naming a local file, a
// program, or another scheme is refused before anything is launched.
#test
{
    Swag.assert(Env.isWebUrl("https://www.swag-lang.org/"))
    Swag.assert(Env.isWebUrl("HTTP://example.com/a?b=c#d"))
    Swag.assert(Env.isWebUrl("mailto:someone@example.com"))

    Swag.assert(not Env.isWebUrl(""))
    Swag.assert(not Env.isWebUrl("file:///C:/Windows/System32/calc.exe"))
    Swag.assert(not Env.isWebUrl("calc.exe"))
    Swag.assert(not Env.isWebUrl("../tools/run.bat"))
    Swag.assert(not Env.isWebUrl("ms-settings:"))
    Swag.assert(not Env.isWebUrl("javascript:alert(1)"))
    Swag.assert(not Env.isWebUrl("https://example.com/a b"))
    Swag.assert(not Env.isWebUrl("https://example.com/\n"))

    Swag.assert(not Env.openUrl("file:///C:/Windows/System32/calc.exe"))
    Swag.assert(not Env.openUrl("calc.exe"))
}

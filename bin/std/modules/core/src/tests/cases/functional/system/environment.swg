#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    Swag.require(not tempDir.isEmpty())
    Swag.require(Path.isRooted(tempDir.toString()))
    Swag.require(Directory.exists(tempDir.toString()))

    let downloadsDir = Env.realSpecialDirectory(.Downloads)
    Swag.require(not downloadsDir.isEmpty())
    Swag.require(Path.isRooted(downloadsDir.toString()))
    Swag.require(Directory.exists(downloadsDir.toString()))

    let sandboxDownloads = Env.getSpecialDirectory(.Downloads)
    Swag.require(Path.isRooted(sandboxDownloads.toString()))
    Swag.require(Directory.exists(sandboxDownloads.toString()))
}

// A '#test' is a program run, whether it executes in the JIT pass of 'swc test' or in the
// generated executable, so both must expose the same command line. The test command always
// injects the 'swag.test' run argument, which makes it the one argument every run is guaranteed
// to see: if 'Swag.args()' comes back empty here, run arguments are not reaching this pass at all and
// nothing can be driven from the command line.
#test
{
    let args = Env.arguments()
    Swag.require(args.count != 0)
    Swag.require(Env.hasArgument("swag.test"))
    Swag.require(not Env.hasArgument("swag.not-a-real-argument"))
    Swag.require(Env.argument(0) == args[0])
    Swag.require(Env.argument(cast(u32, args.count)) == null)
    Swag.require(Env.executablePath() == args[0])
}

// Only absolute web addresses reach the system handler; a document link naming a local file, a
// program, or another scheme is refused before anything is launched.
#test
{
    Swag.require(Env.isWebUrl("https://www.swag-lang.org/"))
    Swag.require(Env.isWebUrl("HTTP://example.com/a?b=c#d"))
    Swag.require(Env.isWebUrl("mailto:someone@example.com"))
    Swag.require(Env.isWebUrl("https://example.com/caf\u00E9"))

    Swag.require(not Env.isWebUrl(""))
    Swag.require(not Env.isWebUrl("file:///C:/Windows/System32/calc.exe"))
    Swag.require(not Env.isWebUrl("calc.exe"))
    Swag.require(not Env.isWebUrl("../tools/run.bat"))
    Swag.require(not Env.isWebUrl("ms-settings:"))
    Swag.require(not Env.isWebUrl("javascript:alert(1)"))
    Swag.require(not Env.isWebUrl("https://example.com/a b"))
    Swag.require(not Env.isWebUrl("https://example.com/\n"))
    Swag.require(not Env.isWebUrl("https://example.com/\u00A0"))

    let invalidUrlBytes: [22] u8 = [
        'h', 't', 't', 'p', 's', ':', '/', '/', 'e', 'x', 'a', 'm', 'p', 'l', 'e', '.', 'c', 'o', 'm', '/',
        0xC0, 0xAF
    ]
    let invalidUrl = Swag.makeString(invalidUrlBytes.buffer, invalidUrlBytes.count)
    Swag.require(not Env.isWebUrl(invalidUrl))

    Swag.require(not Env.openUrl("file:///C:/Windows/System32/calc.exe"))
    Swag.require(not Env.openUrl("calc.exe"))
}

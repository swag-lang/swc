#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    Swag.assert(tempDir.length != 0)
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

// Native windows are returned as scope-bound owning values and can be closed repeatedly.
#test
{
    var window = expect Env.createWindow({
        identifier: "core-environment-test",
        title: "Core environment test",
        width: 64,
        height: 64})
    Swag.assert(window.isOpen())

    expect window.close()
    Swag.assert(!window.isOpen())
    expect window.close()
}

#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    @assert(tempDir.length != 0)
    @assert(Path.isRooted(tempDir.toString()))
    @assert(Directory.exists(tempDir.toString()))
}

// A '#test' is a program run, whether it executes in the JIT pass of 'swc test' or in the
// generated executable, so both must expose the same command line. The test command always
// injects the 'swag.test' run argument, which makes it the one argument every run is guaranteed
// to see: if '@args' comes back empty here, run arguments are not reaching this pass at all and
// nothing can be driven from the command line.
#test
{
    @assert(@countof(Env.arguments()) != 0)
    @assert(Env.hasArgument("swag.test"))
    @assert(@countof(Env.executablePath()) != 0)
}

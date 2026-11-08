#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

const SandboxStartupPeerArg = "--swag-sandbox-startup-peer"
const SandboxStartupOutsideArg = "--swag-sandbox-outside="

#init
{
    if Env.hasArgument(SandboxStartupPeerArg) do
        Swag.require(Env.isSandboxed(), "Core must arm the sandbox before another init hook")
}

#premain
{
    if Env.hasArgument(SandboxStartupPeerArg)
    {
        var outside = ""
        for argument in Env.arguments() where argument.count > SandboxStartupOutsideArg.count and
                                            argument[0 until SandboxStartupOutsideArg.count] == SandboxStartupOutsideArg do
            outside = argument[SandboxStartupOutsideArg.count until argument.count]
        Swag.require(outside.count != 0)
        Swag.require(Env.isSandboxed())
        Swag.require(Env.sandboxRoot() == Path.combine(outside, "root").toString())

        var denied: Swag.Error
        discard catch File.writeAllText(Path.combine(outside, "marker"), "escaped") as denied
        Swag.require(denied.value() is Errors.SandboxError)
        Env.exit(37)
    }
}

#[Swag.TestTag("integration.sandbox")]
#test
{
    Swag.require(not Swag.jit(), "run sandbox startup with --no-test-jit")
    const Template = "/tmp/swag-sandbox-startup-outside-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = Linux.mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    let outside = cast(string, cast(cstring, temporary.buffer))
    let root = Path.combine(outside, "root")
    let marker = Path.combine(outside, "marker")
    defer discard Linux.unlinkat(Linux.AT_FDCWD, temporary.buffer, Linux.AT_REMOVEDIR)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, marker.storage(), 0)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, root.storage(), Linux.AT_REMOVEDIR)

    let sandboxArg = Format.toString("swag.sandbox=%", root)
    let outsideArg = Format.toString("--swag-sandbox-outside=%", outside)
    let arguments = [SandboxStartupPeerArg, sandboxArg.toString(), outsideArg.toString()]
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: arguments,
                                                     standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37, String.from(process.standardError()).toString())
    let escaped = Linux.openat(Linux.AT_FDCWD, marker.storage(), Linux.O_RDONLY, 0)
    if escaped >= 0 do
        discard Linux.close(escaped)
    Swag.require(escaped < 0 and Linux.errno() == Linux.ENOENT)
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Swag

func assertZeroProcessStream(stream: string)
{
    Swag.require(stream.count == 131072)
    for byte in stream do
        Swag.require(byte == 0)
}

// Waiting drains both pipes, including when each stream exceeds its kernel pipe capacity.
#test
{
    let info = Env.StartInfo{
        fileName: "/bin/sh",
        arguments: ["-c", "dd if=/dev/zero bs=131072 count=1 2>/dev/null; dd if=/dev/zero bs=131072 count=1 1>&2 2>/dev/null"],
        standardOutput: .Pipe,
        standardError: .Pipe}

    let process = expect Env.runProcess(info)
    Swag.require(process.exitCode() == 0)
    assertZeroProcessStream(process.standardOutput())
    assertZeroProcessStream(process.standardError())
}

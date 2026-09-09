#global internal
#global namespace Pipeline

using Core

// Formats an isolated snapshot; the caller applies it only if the editor has not changed.
struct SourceFormatter
{
    folder: Probe
}

impl SourceFormatter
{
    mtd format(source: string, cancelled: *u32)->Result fail
    {
        try .folder.open()
        let directory = Path.combine(.folder.root, "src")
        let file      = Path.combine(directory, "source.swg")
        discard try File.writeAllBytes(file, cast(const [..] u8) source)
        let compiler = compilerPath()

        // The formatter skips parse errors by design. Syntax supplies the diagnostics before
        // formatting so an unchanged invalid document is never reported as formatted.
        var result: retval
        for command in ["syntax", "format"]
        {
            if Atomic.get(cancelled) do
                return {}
            let arguments = Env.joinArguments([command, "--num-cores", "6", "--file", file.toString()])
            var process   = try Env.startProcess(Env.StartInfo{fileName: compiler.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
            defer retireProcess(&process)
            var watch: Time.Stopwatch
            watch.start()
            while !try process.tryWaitForExit(20'ms)
            {
                if Atomic.get(cancelled) do
                    return {}
                if watch.elapsedMilliseconds() > 60000 do
                    return {text: String.from("Formatting exceeded 60 seconds."), failed: true}
            }

            if process.exitCode() != 0
            {
                result.failed = true
                result.text   = process.standardOutput()
                result.text.append(process.standardError())
                return result
            }
        }

        let bytes = try File.readAllBytes(file)
        result.text = cast(string) bytes.toSlice()

        // The editor stores LF; its undo records must count the same runes it inserts.
        result.text.replace("\r\n", "\n")

        return result
    }
}

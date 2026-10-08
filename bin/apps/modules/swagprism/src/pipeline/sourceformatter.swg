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
    // Checks the syntax of `source` and formats it with the compiler, out of process; empty when
    // `cancelled` is raised.
    mtd format(source: string, cancelled: *u32)->Result fail
    {
        try .folder.open()
        let file = Path.combine(.folder.root, "src", "source.swg")
        discard try File.writeAllBytes(file, source)
        let compiler = compilerPath()
        let workers  = Format.toString("%", compilerWorkerCount())

        // The formatter skips parse errors by design. Syntax supplies the diagnostics before
        // formatting so an unchanged invalid document is never reported as formatted.
        var result: retval
        for command in ["syntax", "format"]
        {
            if Atomic.get(cancelled) do
                return {}
            let arguments = Env.joinArguments([command, "--num-cores", workers, "--file", file])
            var process   = try startPiped(compiler, arguments)
            defer retireProcess(&process)

            var watch: Time.Stopwatch
            watch.start()
            while not try process.tryWaitForExit(20'ms)
            {
                if Atomic.get(cancelled) do
                    return {}
                if watch.elapsedMilliseconds() > CompilerTimeoutMs do
                    return {text: appStrings().msg_FormatTimeout, failed: true}
            }

            if process.exitCode() != 0
            {
                result.failed = true
                result.text   = process.standardOutput()
                result.text.append(process.standardError())
                return result
            }
        }

        // The editor stores LF; its undo records must count the same runes it inserts.
        result.text = try File.readAllText(file)
        result.text.replace("\r\n", "\n")

        return result
    }
}

#global if #os == Swag.TargetOs.Linux
#global namespace Env

// Linux startup publishes argv before module initialization, in both JIT and native runs.
internal func findRunArgument(name: string)->{ found: bool, value: String } => findRunArgumentIn(Swag.args(), name)

// Canonicalize the longest existing prefix with the filesystem, then collapse the missing
// suffix lexically. A link followed by '..' must be resolved before removing that component.
// Failure is an empty result so containment never falls back to an unsafe textual prefix.
internal func absolutePath(path: string)->String
{
    let absolute = catch Path.absolute(path) { return "" }
    let full     = absolute.toString()
    var end      = full.count
    for
    {
        while end > 1 and full[end - 1] == '/' do
            end -= 1
        let candidate = String.from(full[until end])
        let resolved  = Linux.realpath(candidate.storage(), null)
        if resolved
        {
            defer Linux.free(resolved)
            var result = String.from(cast(string, cast(cstring, resolved)))
            for part in Tokenize.split(full[end to], '/'u8)
            {
                if part == "." do
                    continue
                if part == ".." do
                    result = Path.directoryName(result) orelse "/"
                else do
                    result = Path.combine(result, part)
            }

            return result
        }

        let error = Linux.errno()
        if error == Linux.EINTR do
            continue
        if error != Linux.ENOENT or end == 1 do
            return ""
        while end > 1 and full[end - 1] != '/' do
            end -= 1
        if end > 1 do
            end -= 1
    }
}

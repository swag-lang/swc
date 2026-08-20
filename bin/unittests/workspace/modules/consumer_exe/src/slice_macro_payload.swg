#global private
using Core

// A slice passed to a public macro is detached and cloned across the module boundary. Its
// lowering payload must be rebound to the clone instead of being published twice.
private func workspaceMarkdownAnchor(line: string)->String
{
    var result: retval
    var start = 1'u64
    Utf8.visitRunes(cast(const [..] u8) line[start until @countof(line)]) #code(value, charIndex, byteIndex)
    {
        discard charIndex
        discard byteIndex
        result += value
    }
    return result
}

#test
{
    @assert(workspaceMarkdownAnchor("#hello") == "hello")
}

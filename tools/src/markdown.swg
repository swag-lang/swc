#global namespace Tool

using Core

// The Markdown a repository audit reads: anchors as a `#fragment` resolves them, shared by
// the backlog contract and the third-party notice contract.

// The GitHub anchor rule, which is what every `#fragment` in this repository targets: letters
// and digits are kept and lowercased, a space becomes a dash, and everything else disappears.
func markdownHeadingAnchor(line: string)->String
{
    var result: retval
    var start:  u64
    while start < line.count and start < 6 and line[start] == '#' do
        start += 1
    if start == 0 or start >= line.count or line[start] != ' ' do
        return result

    start += 1
    Utf8.visitRunes(cast(const [..] u8) line[start until line.count]) #code(c, charIndex, byteIndex)
    {
        discard charIndex
        discard byteIndex
        if Unicode.isLetterOrDigit(c) do
            result += Unicode.toLower(c)
        elif c == '-' or c == '_' do
            result += c
        elif c == ' ' do
            result += '-'
    }

    return result
}

// Reports whether the Markdown file holds a heading that answers to that anchor.
func hasMarkdownHeading(fileName: string, anchor: string)->bool fail
{
    let content = try File.readAllText(fileName)
    for line in Tokenize.splitLines(content.toString())
    {
        if markdownHeadingAnchor(line) == anchor do
            return true
    }

    return false
}

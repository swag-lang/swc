#global internal
#global namespace Viewers.Notebook

using Core, Gui

private const FileLimit     = 16 * 1024 * 1024'u64
private const CellTextLimit = 64 * 1024'u64

// The supported, inert subset of a Jupyter notebook. Unknown JSON properties, including widget
// state and executable metadata, are skipped by the strict JSON reader.
struct MimeData
{
    #[Serialization.Key("text/plain")]
    textPlain: Array'String
}

struct StoredOutput
{
    #[Serialization.Key("output_type")]
    outputType: String
    text:       Array'String
    traceback:  Array'String
    #[Serialization.Key("ename")]
    errorName: String
    #[Serialization.Key("evalue")]
    errorValue: String
    data:       MimeData
}

struct Cell
{
    #[Serialization.Key("cell_type")]
    cellType: String
    #[Serialization.Key("execution_count")]
    executionCount: String
    source:         Array'String
    outputs:        Array'StoredOutput
}

struct KernelMetadata
{
    #[Serialization.Key("display_name")]
    displayName: String
    name:        String
    language:    String
}

struct LanguageMetadata
{
    name:    String
    version: String
}

struct NotebookMetadata
{
    kernelspec: KernelMetadata
    #[Serialization.Key("language_info")]
    languageInfo: LanguageMetadata
}

struct Document
{
    cells:    Array'Cell
    metadata: NotebookMetadata
    nbformat: u32
}

private func quotedEnd(source: string, start: u64)->u64
{
    var at = start + 1
    while at < source.count
    {
        if source[at] == '\\'
        {
            at += 2
            continue
        }

        if source[at] == '"' do
            return at
        at += 1
    }

    return Swag.U64.Max
}

// Normalizes scalar cell sources and scalar text/plain MIME values to the array form used by the
// document model. Execution counts become strings so both the usual integer and JSON null remain
// distinguishable in the reader. This lexical transformation leaves all other validation to the
// strict JSON decoder.
private func normalizeSources(source: string)->String
{
    var result: String
    var copiedUntil = 0'u64
    var at = 0'u64
    while at < source.count
    {
        if source[at] != '"'
        {
            at += 1
            continue
        }

        let end = quotedEnd(source, at)
        if end == Swag.U64.Max do
            break
        let field = source[at until end + 1]
        if field != "\"source\"" and field != "\"text/plain\"" and field != "\"execution_count\""
        {
            at = end + 1
            continue
        }

        var colon = end + 1
        while colon < source.count and
              (source[colon] == ' ' or
               source[colon] == '\t' or
               source[colon] == '\r' or
               source[colon] == '\n') do
            colon += 1
        if colon >= source.count or source[colon] != ':'
        {
            at = end + 1
            continue
        }

        var value = colon + 1
        while value < source.count and
              (source[value] == ' ' or
               source[value] == '\t' or
               source[value] == '\r' or
               source[value] == '\n') do
            value += 1
        if value >= source.count
        {
            at = end + 1
            continue
        }

        if field == "\"execution_count\""
        {
            var valueEnd = value
            if source[value] == 'n' and source[value until Math.min(value + 4, source.count)] == "null"
            {
                valueEnd += 4
            }
            else
            {
                if source[value] == '-' do
                    valueEnd += 1
                let digitsStart = valueEnd
                while valueEnd < source.count and Latin1.isDigit(source[valueEnd]) do
                    valueEnd += 1
                if valueEnd == digitsStart
                {
                    at = end + 1
                    continue
                }
            }

            result      += source[copiedUntil until value]
            result      += "\""
            result      += source[value until valueEnd]
            result      += "\""
            copiedUntil = valueEnd
            at          = copiedUntil
            continue
        }

        if value >= source.count or source[value] != '"'
        {
            at = end + 1
            continue
        }

        let valueEnd = quotedEnd(source, value)
        if valueEnd == Swag.U64.Max do
            break
        result      += source[copiedUntil until value]
        result      += "["
        result      += source[value until valueEnd + 1]
        result      += "]"
        copiedUntil = valueEnd + 1
        at          = copiedUntil
    }

    result += source[copiedUntil until source.count]
    return result
}

// Parses and validates a bounded UTF-8 notebook without interpreting code or rich output.
func parseNotebook(source: string)->Document fail
{
    if source.count > FileLimit do
        fail UnsupportedFormatError{"Notebook is too large to open"}

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let normalized = normalizeSources(source)
    return try decoder.readAll'Document(cast(const [..] u8, normalized))[]
}

private func joinLines(lines: Array'String)->String
{
    var result: #returntype
    for line in lines do
        result += line[]
    return result
}

// Keeps Markdown shaping and the document model bounded even when a single cell/output is huge.
private func boundedText(source: string)->String
{
    if source.count <= CellTextLimit do
        return String.from(source)

    var end = CellTextLimit
    while end and (source[end] & 0xC0) == 0x80 do
        end -= 1
    return Format.toString("%\n\n[Cell text truncated at 64 KiB.]", source[0 until end])
}

// Chooses a Markdown fence longer than any backtick run in the content, so notebook text cannot
// terminate its code block and turn stored source into markup.
private func codeFence(source: string)->String
{
    var run, longest: u64
    for c in source
    {
        if c == '`'
        {
            run     += 1
            longest = Math.max(longest, run)
        }
        else
        {
            run = 0
        }
    }

    let fenceLength = Math.max(3, longest + 1)
    var fence: String
    for fenceLength do
        fence += '`'
    return fence
}

private func fenced(source: string)->String
{
    let fence = codeFence(source)
    var result: String = fence
    result += "text\n"
    result += source
    if source.count and source[source.count - 1] != '\n' do
        result += "\n"
    result += fence
    return result
}

private func markdownSafe(source: string)->String
{
    // Raw HTML, image requests, and Markdown links are displayed as inert text. This preserves
    // headings, lists, emphasis and code while preventing notebook-authored resource loads/actions.
    var result: #returntype
    for c in source
    {
        switch c
        {
        case '<': result += "&lt;"
        case '>': result += "&gt;"
        case '[': result += "\\["
        case ']': result += "\\]"
        case '!': result += "\\!"
        default:  result += c
        }
    }

    return result
}

// Converts decoded notebook cells into a reader document. Rich output and all executable content
// are deliberately represented as source notices; no kernel, widget, script, or resource runs.
func renderMarkdown(document: const *Document)->String
{
    var result: #returntype
    result += Format.toString("# Notebook · nbformat %\n\n", document.nbformat)
    var metadata: String
    if not document.metadata.kernelspec.displayName.isEmpty() do
        metadata += Format.toString("Kernel: %\n", boundedText(document.metadata.kernelspec.displayName.toString()))
    if not document.metadata.kernelspec.name.isEmpty() do
        metadata += Format.toString("Kernel identifier: %\n", boundedText(document.metadata.kernelspec.name.toString()))
    if not document.metadata.kernelspec.language.isEmpty() do
        metadata += Format.toString("Kernel language: %\n", boundedText(document.metadata.kernelspec.language.toString()))
    if not document.metadata.languageInfo.name.isEmpty() do
        metadata += Format.toString("Language: %\n", boundedText(document.metadata.languageInfo.name.toString()))
    if not document.metadata.languageInfo.version.isEmpty() do
        metadata += Format.toString("Language version: %\n", boundedText(document.metadata.languageInfo.version.toString()))
    if metadata.count do
        result += "**Notebook metadata**\n\n"
    result += fenced(metadata.toString())
    result += "\n\n"

    for cell, index in document.cells
    {
        let number = index + 1
        if cell.cellType == "markdown"
        {
            result += Format.toString("## Markdown cell %\n\n", number)
            let source = markdownSafe(boundedText(joinLines(cell.source).toString()).toString())
            result += source
            result += "\n\n"
            continue
        }

        if cell.cellType == "code"
        {
            let source = boundedText(joinLines(cell.source).toString())
            let count  = cell.executionCount.isEmpty() or cell.executionCount == "null"
                         ? String.from("In [ ]")
                         : Format.toString("In [%]", cell.executionCount)
            result += Format.toString("## Code cell % · %\n\n%\n\n", number, count, fenced(source.toString()))
            for output in cell.outputs
            {
                var plainText = joinLines(output.text)
                if not plainText.count do
                    plainText = joinLines(output.data.textPlain)
                let plain = boundedText(plainText.toString())
                let trace = boundedText(joinLines(output.traceback).toString())
                if plain.count
                {
                    result += "**Output**\n\n"
                    result += fenced(plain.toString())
                    result += "\n\n"
                }

                if trace.count or output.errorName.count or output.errorValue.count
                {
                    var errorText: String = output.errorValue
                    if trace.count do
                        errorText += Format.toString("\n%", trace)
                    let error = boundedText(errorText.toString())
                    result += Format.toString("**Error · %**\n\n%\n\n", output.errorName, fenced(error.toString()))
                }

                if output.outputType == "display_data" or output.outputType == "execute_result"
                {
                    result += "**Rich output omitted** · HTML, SVG, images, widgets and other MIME data remain available in the notebook source; they are not rendered, executed or fetched.\n\n"
                }
                elif not plain.count and
                     not trace.count and
                     not output.errorName.count and
                     not output.errorValue.count
                {
                    result += "**Rich output omitted** · HTML, SVG, images, widgets and other MIME data remain available in the notebook source; they are not rendered, executed or fetched.\n\n"
                }
            }

            continue
        }

        // Raw or future cell kinds remain visible as inert source with an explicit type label.
        let source = boundedText(joinLines(cell.source).toString())
        result += Format.toString("## % cell % · source\n\n%\n\n", cell.cellType, number, fenced(source.toString()))
    }

    return result
}

private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.head.count < 2 or content.head[0] != '{' do
        return false
    let head = cast(string, content.head)
    return Utf8.contains(head, "\"cells\"") and Utf8.contains(head, "\"nbformat\"")
}

func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "notebook"
        .staticName   = "Notebook"
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Notebook)
        .create       = &createViewer
        .probe        = &pluginProbe
        .textual      = true
        .smokeFixture = "viewer.field-notes.ipynb"
        .addSelectors(".ipynb")
    }

    return result
}

func createViewer(host: Viewer.Host)
{
    let fileName = host.fileName()
    let info     = catch File.info(fileName)
    {
        host.reject("Could not read notebook file information")
        return
    }

    if info.size > FileLimit
    {
        host.reject("Notebook is too large to open")
        return
    }

    let source = catch File.readAllText(fileName)
    {
        host.reject("Could not read notebook source")
        return
    }

    let document = catch parseNotebook(source.toString())
    {
        host.reject("Notebook JSON is invalid or uses an unsupported source shape")
        return
    }

    let rendered = renderMarkdown(&document)
    let view     = Markdown.View.createText(host.contentParent(), rendered.toString(), Markdown.Style.theme())
    host.attachView(view)

    // The heading parser and Markdown view see the same in-memory text, so every outline target
    // is a source offset that revealHeading can navigate to without reopening the notebook file.
    let outline  = DocumentOutline.create(host)
    let headings = Markdown.parseHeadings(rendered.toString())
    outline.publish(headings.toSlice())
    outline.follow      = func|panel = outline, document = view|() { panel.markReading(document.readingOffset(), atEnd: document.readingProgress() >= 1) }
    outline.sigSelected += func|document = view|(_, offset) { discard document.revealHeading(offset) }
    view.sigScrolled    += func|panel = outline|(_) { panel.followOpenReading() }

    host.setDetails("Notebook · code is not executed; active MIME outputs are omitted")
}

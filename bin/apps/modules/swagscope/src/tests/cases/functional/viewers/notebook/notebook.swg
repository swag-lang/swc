#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

#test
{
    let source   = expect File.readAllText(scopeTestDataPath("viewer.field-notes.ipynb"))
    let document = expect Notebook.parseNotebook(source)
    Swag.require(document.nbformat == 4 and document.cells.count == 3)
    Swag.require(document.cells[0].cellType == "markdown" and
                 Utf8.contains(Notebook.joinLines(document.cells[0].source).toString(), "north marsh"))
    Swag.require(document.cells[1].cellType == "code" and document.cells[1].outputs.count == 3)
    Swag.require(document.cells[1].executionCount == "4")
    Swag.require(document.metadata.kernelspec.displayName == "Python 3" and
                 document.metadata.kernelspec.name == "python3")
    Swag.require(Notebook.joinLines(document.cells[1].outputs[0].text).toString() == "site,ph,temperature_c\nnorth-marsh,6.8,14.2\n")
    Swag.require(document.cells[1].outputs[2].errorName == "ValueError")
}

#test
{
    let source   = expect File.readAllText(scopeTestDataPath("viewer.field-notes.ipynb"))
    let document = expect Notebook.parseNotebook(source)
    let rendered = Notebook.renderMarkdown(&document).toString()
    Swag.require(Utf8.contains(rendered, "## Markdown cell 1") and
                 Utf8.contains(rendered, "## Code cell 2 · In [4]") and
                 Utf8.contains(rendered, "Kernel: Python 3") and
                 Utf8.contains(rendered, "north-marsh,6.8,14.2") and
                 Utf8.contains(rendered, "ValueError"))
    Swag.require(Utf8.contains(rendered, "Rich output omitted") and
                 Utf8.contains(rendered, "not rendered, executed or fetched"))
    Swag.require(not Utf8.contains(rendered, "<img") and
                 not Utf8.contains(rendered, "![map]") and
                 not Utf8.contains(rendered, "[external]"))
}

// Notebook metadata is a bounded inert reading; strings that resemble markup remain in a text fence.
#test
{
    let document = expect Notebook.parseNotebook("{\"cells\":[],\"metadata\":{\"kernelspec\":{\"display_name\":\"<script>alert(1)</script>\",\"name\":\"py```\",\"language\":\"python\"},\"language_info\":{\"name\":\"Python\",\"version\":\"3.13\"}},\"nbformat\":4}")
    let rendered = Notebook.renderMarkdown(&document).toString()
    Swag.require(Utf8.contains(rendered, "Kernel: <script>alert(1)</script>") and
                 Utf8.contains(rendered, "Kernel identifier: py```") and
                 Utf8.contains(rendered, "````text") and
                 Utf8.contains(rendered, "Language version: 3.13"))
    Swag.require(not Utf8.contains(rendered, "<script>alert(1)</script>\n\n"))
}

#test
{
    var large: String
    for 70 * 1024 do
        large += 'x'
    let bounded = Notebook.boundedText(large.toString()).toString()
    Swag.require(bounded.count < large.count and Utf8.contains(bounded, "truncated at 64 KiB"))
}

#test
{
    let document = expect Notebook.parseNotebook("{\"cells\":[{\"cell_type\":\"markdown\",\"source\":\"# Scalar source\\nbody\"}],\"nbformat\":4}")
    Swag.require(document.cells.count == 1 and
                 Notebook.joinLines(document.cells[0].source).toString() == "# Scalar source\nbody")
}

#test
{
    let document = expect Notebook.parseNotebook("{\"cells\":[{\"cell_type\":\"code\",\"source\":[\"snippet = ```\\n<script>alert(1)</script>\"]}],\"nbformat\":4}")
    let rendered = Notebook.renderMarkdown(&document).toString()
    Swag.require(Utf8.contains(rendered, "````text") and Utf8.contains(rendered, "<script>alert(1)</script>"))
}

// Standard display_data text/plain remains readable while sibling HTML/SVG MIME payloads stay inert.
#test
{
    let source   = expect File.readAllText(scopeTestDataPath("viewer.field-display.ipynb"))
    let document = expect Notebook.parseNotebook(source)
    let output   = document.cells[1].outputs[0]
    Swag.require(output.data.textPlain.count == 3 and
                 Notebook.joinLines(output.data.textPlain).toString() == "station  readings  median_ph\nnorth    3         6.9\nsouth    2         7.1\n")

    let rendered = Notebook.renderMarkdown(&document).toString()
    Swag.require(Utf8.contains(rendered, "north    3         6.9") and
                 Utf8.contains(rendered, "Rich output omitted") and
                 Utf8.contains(rendered, "not rendered, executed or fetched"))
    Swag.require(not Utf8.contains(rendered, "<table>") and
                 not Utf8.contains(rendered, "<svg>") and
                 not Utf8.contains(rendered, "active content"))
}

// Jupyter producers may store one plain MIME value as a scalar instead of an array.
#test
{
    let document = expect Notebook.parseNotebook("{\"cells\":[{\"cell_type\":\"code\",\"execution_count\":null,\"source\":[],\"outputs\":[{\"output_type\":\"display_data\",\"data\":{\"text/plain\":\"single result\"}}]}],\"nbformat\":4}")
    Swag.require(Notebook.joinLines(document.cells[0].outputs[0].data.textPlain).toString() == "single result")
    Swag.require(document.cells[0].executionCount == "null" and
                 Utf8.contains(Notebook.renderMarkdown(&document).toString(), "## Code cell 1 · In [ ]"))
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let fileName = scopeTestDataPath("viewer.field-notes.ipynb")
    let result   = openTestViewer(Notebook.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null and result.view is Markdown.View)
    Swag.require(Utf8.contains(result.details, "code is not executed"))
}

// Notebook Markdown headings from both authored cells and the rendered cell labels navigate to
// their exact source positions, without resolving offsets against the original JSON file.
#test
{
    var host: Testing.HeadlessHost
    let window  = framedViewerWindow(&host, scopeTestDataPath("viewer.field-notes.ipynb"), false)
    let view    = assume cast(*Markdown.View, window.currentView)
    let outline = assume cast(*DocumentOutline, window.currentSidePanelHost!.children[0].children[0])
    Swag.require(outline.rows.count >= 5 and outline.rowTitles[2].toString() == "Wetland survey")
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)

    outline.list.selectLine(3)     // The code cell heading is an outline destination too.
    let codeCell = outline.headings[3].sourceOffset
    Swag.require(view.readingOffset() == codeCell)
    outline.list.selectLine(2)     // An authored Markdown heading remains navigable after sanitization.
    Swag.require(view.readingOffset() == outline.headings[2].sourceOffset)
}

#test
{
    var errorOutcome: Swag.Error
    discard catch Notebook.parseNotebook("{\"cells\": [\"unfinished\"]") as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

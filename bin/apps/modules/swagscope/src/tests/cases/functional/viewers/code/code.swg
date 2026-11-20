#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

private var g_CodeReportedDetails: String
private func reportCodeDetails(_: *Wnd, details: string) { g_CodeReportedDetails = details }

func codeFixturePath(name: string)->String => Path.combine(scopeTestDataDirectory(), name)

// Per-file language choices survive reopen, stay isolated between similar paths, and are tied to
// the current file metadata. The preference record accepts only shipped language names.
#test
{
    let temp = Gui.Testing.tempFilePath("scope-code-override-root-", ".tmp")
    let base = Path.directoryName(temp) orelse "."
    let root = Path.combine(base, Format.toString("scope-code-override-%", Guid128.random()))
    defer discard catch Directory.delete(root, recurse: true)
    let preferences = Path.combine(root, "preferences")
    let firstPath = Path.combine(root, "src", "main.cpp")
    let nearbyPath = Path.combine(root, "tests", "main.cpp")
    expect Directory.create(Path.directoryName(firstPath) orelse root, recurse: true)
    expect Directory.create(Path.directoryName(nearbyPath) orelse root, recurse: true)
    discard expect File.writeAllText(firstPath, "int main() { return 0; }\n")
    discard expect File.writeAllText(nearbyPath, "int test() { return 1; }\n")

    let oldPreferenceDirectory = Code.g_CodeOverrideDirectory
    Code.g_CodeOverrideDirectory = preferences
    defer Code.g_CodeOverrideDirectory = oldPreferenceDirectory

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var view = Code.Panel.create(&host.root, firstPath)
    view.highlightAs(.Python)
    Swag.require(view.languageName == "Python")
    view.destroy()

    view = Code.Panel.create(&host.root, firstPath)
    Swag.require(view.languageName == "Python")
    view.destroy()

    let nearby = Code.Panel.create(&host.root, nearbyPath)
    Swag.require(nearby.languageName == "C++")
    nearby.destroy()

    // Plain Text is an explicit choice too, and it remains attached to this exact file version.
    view = Code.Panel.create(&host.root, firstPath)
    view.highlightAs(.PlainText)
    view.destroy()
    view = Code.Panel.create(&host.root, firstPath)
    Swag.require(view.languageName == Code.texts().ui_PlainText)
    view.destroy()

    // Replacing the contents at the same path changes its identity, so the old choice is ignored.
    expect File.delete(firstPath)
    discard expect File.writeAllText(firstPath, "int replacement() { return 123456; }\n")
    view = Code.Panel.create(&host.root, firstPath)
    Swag.require(view.languageName == "C++")
    view.destroy()

    // A crafted unsupported value is rejected and detection still supplies a usable lexer.
    let unsupportedPath = Path.combine(root, "src", "unsupported.cpp")
    discard expect File.writeAllText(unsupportedPath, "int unsupported;\n")
    let preferencePath = Code.languageOverridePath(unsupportedPath)
    expect Directory.create(preferences, recurse: true)
    discard expect File.writeAllText(preferencePath,
                                     Format.toString("SwagScope code language v1\n%\nBrainfuck\n",
                                                     Code.languageOverrideIdentity(unsupportedPath)))
    view = Code.Panel.create(&host.root, unsupportedPath)
    Swag.require(view.languageName == "C++")
    Swag.require(view.languageEvidence != "manual selection")
    view.destroy()
}

// A generated field-station sample colors realistic C++ declarations, literals, and comments.
#test
{
    let source = expect File.readAllText(codeFixturePath("viewer.field-station.cpp"))

    var host: Testing.HeadlessHost
    host.setup(640, 180)
    let editor = RichEditCtrl.create(&host.root, {0, 0, 620, 160})
    var lexer: Code.GenericLexer
    lexer.configure(.Cpp)
    editor.setLexer(&lexer)
    editor.setText(source)
    editor.lexAll()

    let styles = editor.textAndStyles().styles
    Swag.require(styles[source.indexOf("constexpr")] == Code.GenericLexer.Style.Keyword)
    Swag.require(styles[source.indexOf("0.80")] == Code.GenericLexer.Style.Number)
    Swag.require(styles[source.indexOf("\"review\"")] == Code.GenericLexer.Style.String)
    let comment = source.indexOf("Fictional measurements")
    Swag.require(comment != Swag.U64.Max and styles[comment] == Code.GenericLexer.Style.Comment)
}

// Language detection explains the interpreter line when a script has no informative extension.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-shebang-", ".script")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "#!/usr/bin/env python3\nprint('field report')\n")
    Swag.require(Code.detectLanguage(fileName) == .Python)
    Swag.require(Code.detectionEvidence(fileName) == Code.texts().ui_ShebangEvidence)
}

struct CodeLanguageSample
{
    language: Code.SourceLanguage
    source:   string
}

// Unsupported source bytes cross the viewer boundary without being written into the editor.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-", ".cpp")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, [0x66'u8, 0x6F'u8, 0x00'u8, 0x6F'u8])

    var host: Testing.HeadlessHost
    host.setup(640, 420)

    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view == null and result.commands == null)
    Swag.require(Utf8.contains(result.failureReason.toSlice(), Code.texts().err_ZeroByte))
}

// A resident window revealed deep in a long source keeps numbering the lines of the whole file,
// counting forward from the window already numbered and back from the start of the file.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-lines-", ".cpp")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 40_000 do
        source += Format.toString("int value% = %;\n", index, index)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Code.Panel, result.view)
    Swag.require(view.editor.flags.has(.LineNumbers))

    let line30000 = source.indexOf("int value30000 ")
    Swag.require(view.revealOffset(line30000, "value30000"))
    Swag.require(view.residentStart > 0 and view.lines.numberedOffset == view.residentStart)
    Swag.require(view.lines.numberedLine == view.lines.lineAt(fileName, view.residentStart))
    Swag.require(view.lines.lineAt(fileName, line30000) == 30_001)
    Swag.require(view.lines.lineAt(fileName, source.indexOf("int value12 ")) == 13)
    Swag.require(view.lines.lineAt(fileName, 0) == 1)

    // A window too far from any counted line goes without numbers, and they come back with the
    // next window that can be counted.
    view.residentStart = Swag.U64.Max / 2
    view.numberWindow()
    Swag.require(not view.editor.flags.has(.LineNumbers))
    Swag.require(view.revealOffset(0, ""))
    Swag.require(view.editor.flags.has(.LineNumbers))
}

// The whole file is counted in the background apart from the streamed window, so the sheet gives
// its lines and how they end once the count arrives.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-ends-", ".cpp")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "int a;\r\nint b;\r\nint c;\r\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Code.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.statisticsLoad)
    Swag.require(view.hasStatistics and view.statistics.crlf == 3)

    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "3 lines\n"))
    Swag.require(Utf8.contains(text, "Line ends\nCRLF"))
    Swag.require(not Utf8.contains(text, "words"))
}

// The code zoom value keeps the shared information-band air outside its button frame.
#test
{
    let fileName = codeFixturePath("sample.cpp")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, infoParent: &host.root)
    Swag.require(result.view != null and result.info != null)
    let view = assume cast(*Code.Panel, result.view)
    let zoom = view.zoomPercent
    defer view.setZoom(zoom)
    assertViewerInfoButton(unwrap view.zoomLabel)
    Swag.require(result.info.preferredSize.x == Viewer.ZoomSlotWidth)

    view.setZoom(150)
    let editor = view.editor
    let oldTip = String.from(view.zoomLabel.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.zoomLabel.toolTip == Code.texts().ui_ZoomMenu)
    Swag.require(view.zoomPercent == 150 and view.editor == editor)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.zoomLabel.toolTip == oldTip)
}

// End opens a bounded tail window instead of materializing every preceding byte.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-stream-", ".swg")
    defer discard catch File.delete(fileName)
    var source: String
    for 2_000 do
        source += "func streamedValue()->u32 => 42\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    with let view = Code.Panel.create(&host.root, fileName)
    {
        .resize(640, 360)
        .applyLayout()
    }

    let beforeEnd = view.editor.scrollPosition()
    var end       = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    Swag.require(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    Swag.require(view.editor.scrollPosition().y > beforeEnd.y)
}

// Keeps the code viewer's estimated document extent from shrinking while multiple chunks are
// appended without an intervening paint, while the focused editor honors every navigation tier.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-large-scroll-", ".swg")
    defer discard catch File.delete(fileName)
    var source: String
    for 90_000 do
        source += "func streamedValue()->u32 => 42\n"
    Swag.require(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    with let view = Code.Panel.create(&host.root, fileName)
    {
        .resize(640, 360)
        .applyLayout()
    }

    discard host.render(view)
    view.updateEstimatedHeight()

    view.setInitialFocus(view.editor)
    Swag.require(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    Swag.require(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    Swag.require(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    Swag.require(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    Swag.require(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    Swag.require(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 8
    {
        view.loadNextChunk()
        Swag.require(view.virtualHeight >= firstVirtualHeight)
        Swag.require(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    host.keyPress(Input.Key.End)
    discard host.render(view)
    Swag.require(view.residentStart > 0)
    Swag.require(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    Swag.require(view.residentStart == 0)
    Swag.require(view.editor.selectionEnd().lineIndex == 0)
    Swag.require(view.editor.scrollPosition().y == 0)
}

#test
{
    Swag.require(File.exists(codeFixturePath("sample.cpp")))
    Swag.require(File.exists(codeFixturePath("sample.json")))
    Swag.require(Code.detectLanguage("sample.cpp") == .Cpp)
    Swag.require(Code.detectLanguage("sample.cs") == .CSharp)
    Swag.require(Code.detectLanguage("sample.tsx") == .TypeScript)
    Swag.require(Code.detectLanguage("sample.py") == .Python)
    Swag.require(Code.detectLanguage("sample.rs") == .Rust)
    Swag.require(Code.detectLanguage("sample.sql") == .Sql)
    Swag.require(Code.detectLanguage("sample.yaml") == .Yaml)
    Swag.require(Code.detectLanguage("sample.csproj") == .Xml)
    Swag.require(Code.detectLanguage("sample.html") == .Html)
    Swag.require(Code.detectLanguage("sample.asm") == .Assembly)
    Swag.require(Code.detectLanguage("sample.zig") == .Zig)
    Swag.require(Code.detectLanguage("sample.nim") == .Nim)
    Swag.require(Code.detectLanguage("sample.hs") == .Haskell)
    Swag.require(Code.detectLanguage("sample.scala") == .Scala)
    Swag.require(Code.detectLanguage("sample.groovy") == .Groovy)
    Swag.require(Code.detectLanguage("sample.exs") == .Elixir)
    Swag.require(Code.detectLanguage("sample.erl") == .Erlang)
    Swag.require(Code.detectLanguage("sample.clj") == .Clojure)
    Swag.require(Code.detectLanguage("sample.jl") == .Julia)
    Swag.require(Code.detectLanguage("sample.f90") == .Fortran)
    Swag.require(Code.detectLanguage("sample.pas") == .Pascal)
    Swag.require(Code.detectLanguage("sample.d") == .D)
    Swag.require(Code.detectLanguage("sample.mm") == .ObjectiveC)
    Swag.require(Code.detectLanguage("sample.m") == .Matlab)
    Swag.require(Code.detectLanguage("sample.tcl") == .Tcl)
    Swag.require(Code.detectLanguage("sample.awk") == .Awk)
    Swag.require(Code.detectLanguage("sample.vim") == .Vim)
    Swag.require(Code.detectLanguage("sample.tex") == .Latex)
    Swag.require(Code.detectLanguage("sample.proto") == .Protobuf)
    Swag.require(Code.detectLanguage("sample.graphql") == .GraphQl)
    Swag.require(Code.detectLanguage("sample.gradle") == .Gradle)
    Swag.require(Code.detectLanguage("Makefile") == .Makefile)
    Swag.require(Code.detectLanguage("Dockerfile") == .Dockerfile)
    Swag.require(Code.detectLanguage("sample.nix") == .Nix)
    Swag.require(Code.detectionEvidence("Dockerfile") == Format.toString(Code.texts().ui_FilenameEvidence, "dockerfile"))
    Swag.require(Code.detectionEvidence("sample.cpp") == Format.toString(Code.texts().ui_ExtensionEvidence, ".cpp"))

    var lexer: Code.GenericLexer
    var host:  Testing.HeadlessHost
    host.setup(640, 180)
    let editor = RichEditCtrl.create(&host.root, {0, 0, 620, 160})
    lexer.configure(.TypeScript)
    editor.setLexer(&lexer)
    editor.setText("export async function answer(): Promise<number> { return 42; } // typed")
    editor.lexAll()

    let content = editor.textAndStyles()
    Swag.require(content.styles[0] == Code.GenericLexer.Style.Keyword)
    Swag.require(content.styles[7] == Code.GenericLexer.Style.Keyword)
    Swag.require(content.styles[13] == Code.GenericLexer.Style.Keyword)
    Swag.require(content.styles[content.styles.count - 1] == Code.GenericLexer.Style.Comment)

    const Samples: [26] CodeLanguageSample = [
        CodeLanguageSample{.Html, "<main>content</main>"},
        CodeLanguageSample{.Assembly, "MOV eax, ebx ; comment"},
        CodeLanguageSample{.Zig, "const answer = 42;"},
        CodeLanguageSample{.Nim, "proc answer(): int = 42"},
        CodeLanguageSample{.Haskell, "module Answer where"},
        CodeLanguageSample{.Scala, "class Answer"},
        CodeLanguageSample{.Groovy, "class Answer"},
        CodeLanguageSample{.Elixir, "def answer do 42 end"},
        CodeLanguageSample{.Erlang, "case Value of ok -> true end"},
        CodeLanguageSample{.Clojure, "defn answer [] 42"},
        CodeLanguageSample{.Julia, "function answer() 42 end"},
        CodeLanguageSample{.Fortran, "PROGRAM ANSWER"},
        CodeLanguageSample{.Pascal, "program Answer;"},
        CodeLanguageSample{.D, "module answer;"},
        CodeLanguageSample{.ObjectiveC, "@interface Answer"},
        CodeLanguageSample{.Matlab, "function answer()"},
        CodeLanguageSample{.Tcl, "proc answer {} { return 42 }"},
        CodeLanguageSample{.Awk, "BEGIN { print 42 }"},
        CodeLanguageSample{.Vim, "function Answer()"},
        CodeLanguageSample{.Latex, "\\section{Answer}"},
        CodeLanguageSample{.Protobuf, "message Answer {}"},
        CodeLanguageSample{.GraphQl, "type Answer { value: Int }"},
        CodeLanguageSample{.Gradle, "class Answer {}"},
        CodeLanguageSample{.Makefile, "include common.mk"},
        CodeLanguageSample{.Dockerfile, "FROM scratch"},
        CodeLanguageSample{.Nix, "let answer = 42; in answer"}]

    for sample in Samples
    {
        var sampleLexer: Code.GenericLexer
        sampleLexer.configure(sample.language)
        editor.setLexer(&sampleLexer)
        editor.setText(sample.source)
        editor.lexAll()
        Swag.require(editor.textAndStyles().styles[0] == Code.GenericLexer.Style.Keyword)
    }
}

// An unmatched delimiter leaves the caret in place and explains that the available source has no partner.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-unmatched-", ".c")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "int main() {\n    return 0;\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var services: Viewer.HostServices
    services.reportDetails = &reportCodeDetails
    g_CodeReportedDetails.clear()
    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root, services: services)
    let view   = assume cast(*Code.Panel, result.view)
    discard host.render(view)

    view.editor.setCursorPos({0, 11})
    Swag.require(not view.goToMatchingDelimiter())
    Swag.require(view.editor.cursorLogicalLineIndex() == 0 and view.editor.cursorLogicalCharPos() == 11)
    Swag.require(g_CodeReportedDetails == Format.toString(Code.texts().ui_DelimiterUnavailable, view.languageName))
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-tokens-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "readonly value #sanity Swag.safetyPanic #raw do")

    var host: Testing.HeadlessHost
    host.setup(640, 160)
    let view = Code.Panel.create(&host.root, fileName)
    view.editor.lexAll()
    Swag.require(view.editor.runeAt({0, 0}).style == RichEditLexerSwag.Style.Keyword)
    Swag.require(view.editor.runeAt({0, 15}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.require(view.editor.runeAt({0, 23}).style == RichEditLexerSwag.Style.Namespace)
    Swag.require(view.editor.runeAt({0, 27}).style == RichEditLexerSwag.Style.Default)
    Swag.require(view.editor.runeAt({0, 28}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.require(view.editor.runeAt({0, 40}).style == RichEditLexerSwag.Style.Keyword)
    Swag.require(view.editor.runeAt({0, 45}).style == RichEditLexerSwag.Style.Control)
}

// The generic lexer colors strings, numbers, calls, and types in code, and the tags, attribute
// values, and comments of markup.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 180)
    let editor = RichEditCtrl.create(&host.root, {0, 0, 620, 160})

    var code: Code.GenericLexer
    code.configure(.TypeScript)
    editor.setLexer(&code)
    editor.setText("let s = \"x\"; f(12); Box")
    editor.lexAll()
    let codeStyles = editor.textAndStyles().styles
    Swag.require(codeStyles[8] == Code.GenericLexer.Style.String)
    Swag.require(codeStyles[13] == Code.GenericLexer.Style.Function)
    Swag.require(codeStyles[15] == Code.GenericLexer.Style.Number)
    Swag.require(codeStyles[20] == Code.GenericLexer.Style.Type)

    var markup: Code.GenericLexer
    markup.configure(.Html)
    editor.setLexer(&markup)
    editor.setText("<a href=\"u\">t</a><!-- c -->")
    editor.lexAll()
    let markupStyles = editor.textAndStyles().styles
    Swag.require(markupStyles[0] == Code.GenericLexer.Style.Keyword)
    Swag.require(markupStyles[8] == Code.GenericLexer.Style.String)
    Swag.require(markupStyles[12] == Code.GenericLexer.Style.Default)
    Swag.require(markupStyles[17] == Code.GenericLexer.Style.Comment)
}

// Marking the blanks of source code is a lens command whose choice follows the reader to the next
// source file.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-blanks-", ".c")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "int main()\n{\n\treturn 0;\n}\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var first = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view  = assume cast(*Code.Panel, first.view)
    Swag.require(not view.editor.flags.has(.DrawBlanks))

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Code", host.theme)
    view.describeLens(&entries)
    var found = false
    for &entry in results.sections[0]!.entries where entry.title == Code.texts().ui_Blanks
    {
        Swag.require(not entry.checked)
        entry.run!()
        found = true
    }

    Swag.require(found and view.editor.flags.has(.DrawBlanks) and view.editor.flags.has(.LineNumbers))
    defer view.toggleBlanks()

    var second = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let next   = assume cast(*Code.Panel, second.view)
    Swag.require(next.editor.flags.has(.DrawBlanks))
}

// The tab stops of source code are a lens choice: the tabulation of the line widens with them,
// and the choice follows the reader to the next source file.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-tabs-", ".c")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "int main()\n{\n\treturn 0;\n}\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var first = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view  = assume cast(*Code.Panel, first.view)
    Swag.require(view.editor.tabSize == 4)
    discard host.render(view)
    let four = view.editor.cursorDisplayPosition({2, 1}).x

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Code", host.theme)
    view.describeLens(&entries)
    for &entry in results.sections[0]!.entries do
        Swag.require(not Utf8.startsWith(entry.title, Code.texts().ui_TabWidth), "an empty lens lists no tab stops")
    var tabResults = Testing.lensResults("tab")
    var tabs       = Viewer.LensEntries.create(&tabResults, "Code", host.theme)
    view.describeLens(&tabs)
    var checked: Array'String
    var found = false
    for &entry in tabResults.sections[0]!.entries
    {
        if entry.checked do
            checked.add(entry.title)
        if entry.title == Viewer.tabWidthRowText(Code.texts().ui_TabWidth, 8)
        {
            entry.run!()
            found = true
        }
    }

    defer view.setTabWidth(4)
    Swag.require(found and
                 Slice.contains(checked.toSlice(), Viewer.tabWidthRowText(Code.texts().ui_TabWidth, 4)) and
                 not Slice.contains(checked.toSlice(), Viewer.tabWidthRowText(Code.texts().ui_TabWidth, 8)))
    discard host.render(view)
    let eight = view.editor.cursorDisplayPosition({2, 1}).x
    Swag.require(view.editor.tabSize == 8 and eight > four, Format.toString("% then %", four, eight))

    var second = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let next   = assume cast(*Code.Panel, second.view)
    Swag.require(next.editor.tabSize == 8)
}

// A typed language name in the lens colors the source as that language, whatever its name says;
// the summary names the language in force, and an empty query offers no language list.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-language-", ".c")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "def main():\n    return 0\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Code.Panel, result.view)
    Swag.require(view.languageName == "C")

    var quiet: Lens.Results
    var quietRows = Viewer.LensEntries.create(&quiet, "Code", host.theme)
    view.describeLens(&quietRows)
    for entry in quiet.sections[0]!.entries do
        Swag.require(not Utf8.startsWith(entry.title.toString(), "Highlight as"), entry.title.toString())

    var results = Testing.lensResults("python")
    var entries = Viewer.LensEntries.create(&results, "Code", host.theme)
    view.describeLens(&entries)
    var chosen = 0
    for &entry in results.sections[0]!.entries where entry.title == Format.toString(Code.texts().ui_HighlightAs, "Python")
    {
        Swag.require(not entry.checked)
        entry.run!()
        chosen += 1
    }

    Swag.require(chosen == 1 and view.languageName == "Python")
}

// Plain Text is a manual language choice that removes all syntax colors from a generated C++ sample.
#test
{
    let fileName = codeFixturePath("viewer.field-station.cpp")
    let source   = expect File.readAllText(fileName)
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    let result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Code.Panel, result.view)
    view.editor.lexAll()
    let colored = view.editor.textAndStyles().styles
    Swag.require(colored[source.indexOf("constexpr")] == Code.GenericLexer.Style.Keyword)

    var results = Testing.lensResults("Plain Text")
    var entries = Viewer.LensEntries.create(&results, "Code", host.theme)
    view.describeLens(&entries)
    var chosen = 0
    let label = Format.toString(Code.texts().ui_HighlightAs, Code.texts().ui_PlainText)
    for &entry in results.sections[0]!.entries where entry.title == label
    {
        entry.run!()
        chosen += 1
    }

    Swag.require(chosen == 1 and view.languageName == Code.texts().ui_PlainText)
    for style in view.editor.textAndStyles().styles do
        Swag.require(style == Code.GenericLexer.Style.Default)
}

// Ctrl+] moves the caret to the bracket pairing with the one at it, either way, and a brace inside
// a string pairs with nothing in the code around it.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-code-pairs-", ".c")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "int f(int a)\n{\n    if (a) { return \"}\"; }\n    return 0;\n}\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Code.Panel, result.view)
    discard host.render(view)

    view.editor.setCursorPos({1, 0})
    Swag.require(view.goToMatchingDelimiter())
    Swag.require(view.editor.cursorLogicalLineIndex() == 4 and view.editor.cursorLogicalCharPos() == 0, Format.toString("% %", view.editor.cursorLogicalLineIndex(), view.editor.cursorLogicalCharPos()))

    // Just after a closing bracket, the caret goes back to the one that opens it.
    view.editor.setCursorPos({4, 1})
    Swag.require(view.goToMatchingDelimiter())
    Swag.require(view.editor.cursorLogicalLineIndex() == 1 and view.editor.cursorLogicalCharPos() == 0)

    view.editor.setCursorPos({0, 5})
    Swag.require(view.goToMatchingDelimiter() and
                 view.editor.cursorLogicalLineIndex() == 0 and
                 view.editor.cursorLogicalCharPos() == 11)

    view.editor.setCursorPos({3, 2})
    Swag.require(not view.goToMatchingDelimiter())

    // The window read again is colored again before a pair is sought in it.
    Swag.require(view.revealOffset(0, ""))
    view.editor.setCursorPos({1, 0})
    Swag.require(view.goToMatchingDelimiter() and view.editor.cursorLogicalLineIndex() == 4)

    // The lens offers the pair only beside a bracket.
    for line, index in [3'u64, 1'u64]
    {
        view.editor.setCursorPos({line, index == 0 ? 2'u64 : 0'u64})
        var results: Lens.Results
        var entries = Viewer.LensEntries.create(&results, "Code", host.theme)
        view.describeLens(&entries)
        var offered = false
        for &entry in results.sections[0]!.entries where entry.title == Code.texts().ui_MatchingDelimiter do
            offered = true
        Swag.require(offered == (index == 1))
    }
}

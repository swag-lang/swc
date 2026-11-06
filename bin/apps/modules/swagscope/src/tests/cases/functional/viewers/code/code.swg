#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func codeFixturePath(name: string)->String => Path.combine(scopeTestDataDirectory(), name)

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
    Swag.require(view.zoomLabel.toolTip == Code.texts().ui_ZoomMenu and view.zoomLabel.toolTip != oldTip)
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

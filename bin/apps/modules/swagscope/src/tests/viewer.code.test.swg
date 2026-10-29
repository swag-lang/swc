#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func codeFixturePath(name: string)->String => Path.combine(Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas"), name)

// Builds the Swag document the highlighting test lexes.
//
// This one fixture is written at run time instead of being stored under `datas`: the compiler
// collects every '.swg' below `src` with no exception for a test folder, so a file keeping the
// extension the lexer is selected by would be compiled into the viewer and would publish its
// declarations as part of it.
func swagSampleSource()->String
{
    var result: #returntype
    result += "#global public\n"
    result += "\n"
    result += "using Core\n"
    result += "\n"
    result += "// Swag lexer verification fixture.\n"
    result += "func answer(value: u32)->u32\n"
    result += "{\n"
    result += "    let doubled = value * 2\n"
    result += "    if doubled > 40 do\n"
    result += "        return doubled + 2\n"
    result += "    return 0\n"
    result += "}\n"
    return result
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
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(Utf8.contains(result.failureReason.toSlice(), Code.texts().err_ZeroByte))
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
    Swag.assert(view.editor.flags.has(.LineNumbers))

    let line30000 = source.indexOf("int value30000 ")
    Swag.assert(view.revealOffset(line30000, "value30000"))
    Swag.assert(view.residentStart > 0 and view.lines.numberedOffset == view.residentStart)
    Swag.assert(view.lines.numberedLine == view.lines.lineAt(fileName, view.residentStart))
    Swag.assert(view.lines.lineAt(fileName, line30000) == 30_001)
    Swag.assert(view.lines.lineAt(fileName, source.indexOf("int value12 ")) == 13)
    Swag.assert(view.lines.lineAt(fileName, 0) == 1)
}

// The code zoom value keeps the shared information-band air outside its button frame.
#test
{
    let fileName = codeFixturePath("sample.cpp")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, infoParent: &host.root)
    Swag.assert(result.view != null and result.info != null)
    let view = assume cast(*Code.Panel, result.view)
    assertViewerInfoButton(unwrap view.zoomLabel)
    Swag.assert(result.info.preferredSize.x == Viewer.ZoomSlotWidth)

    view.setZoom(150)
    let editor = view.editor
    let oldTip = String.from(view.zoomLabel.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.zoomLabel.toolTip == Code.texts().ui_ZoomMenu and view.zoomLabel.toolTip != oldTip)
    Swag.assert(view.zoomPercent == 150 and view.editor == editor)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(view.zoomLabel.toolTip == oldTip)
}

#[Swag.TestTag("golden")]
#test
{
    let source   = swagSampleSource()
    let fileName = Gui.Testing.tempFilePath("scope-code-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Code.Panel.create(&host.root, fileName)
    view.setZoom(150)
    Swag.assert(view.zoomPercent == 150)
    view.setZoom(100)
    view.resize(640, 360)
    view.applyLayout()
    view.editor.lexAll()

    // RichEdit stores logical line breaks as LF, which is what the document was written with.
    let content  = view.editor.textAndStyles()
    let expected = source.toRuneArray()
    Swag.assert(Utf8.fromUnicode(content.text.toSlice()) == Utf8.fromUnicode(expected.toSlice()))
    var colored: bool
    for style in content.styles where style != 0
    {
        colored = true
        break
    }

    Swag.assert(colored)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.code.document")
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
    Swag.assert(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    Swag.assert(view.editor.scrollPosition().y > beforeEnd.y)
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
    Swag.assert(source.length >= 2 * 1024 * 1024)
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
    Swag.assert(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    Swag.assert(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    Swag.assert(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    Swag.assert(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    Swag.assert(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    Swag.assert(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 8
    {
        view.loadNextChunk()
        Swag.assert(view.virtualHeight >= firstVirtualHeight)
        Swag.assert(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    host.keyPress(Input.Key.End)
    discard host.render(view)
    Swag.assert(view.residentStart > 0)
    Swag.assert(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    Swag.assert(view.residentStart == 0)
    Swag.assert(view.editor.selectionEnd().lineIndex == 0)
    Swag.assert(view.editor.scrollPosition().y == 0)
}

#test
{
    Swag.assert(File.exists(codeFixturePath("sample.cpp")))
    Swag.assert(File.exists(codeFixturePath("sample.json")))
    Swag.assert(Code.detectLanguage("sample.cpp") == .Cpp)
    Swag.assert(Code.detectLanguage("sample.cs") == .CSharp)
    Swag.assert(Code.detectLanguage("sample.tsx") == .TypeScript)
    Swag.assert(Code.detectLanguage("sample.py") == .Python)
    Swag.assert(Code.detectLanguage("sample.rs") == .Rust)
    Swag.assert(Code.detectLanguage("sample.sql") == .Sql)
    Swag.assert(Code.detectLanguage("sample.yaml") == .Yaml)
    Swag.assert(Code.detectLanguage("sample.csproj") == .Xml)
    Swag.assert(Code.detectLanguage("sample.html") == .Html)
    Swag.assert(Code.detectLanguage("sample.asm") == .Assembly)
    Swag.assert(Code.detectLanguage("sample.zig") == .Zig)
    Swag.assert(Code.detectLanguage("sample.nim") == .Nim)
    Swag.assert(Code.detectLanguage("sample.hs") == .Haskell)
    Swag.assert(Code.detectLanguage("sample.scala") == .Scala)
    Swag.assert(Code.detectLanguage("sample.groovy") == .Groovy)
    Swag.assert(Code.detectLanguage("sample.exs") == .Elixir)
    Swag.assert(Code.detectLanguage("sample.erl") == .Erlang)
    Swag.assert(Code.detectLanguage("sample.clj") == .Clojure)
    Swag.assert(Code.detectLanguage("sample.jl") == .Julia)
    Swag.assert(Code.detectLanguage("sample.f90") == .Fortran)
    Swag.assert(Code.detectLanguage("sample.pas") == .Pascal)
    Swag.assert(Code.detectLanguage("sample.d") == .D)
    Swag.assert(Code.detectLanguage("sample.mm") == .ObjectiveC)
    Swag.assert(Code.detectLanguage("sample.m") == .Matlab)
    Swag.assert(Code.detectLanguage("sample.tcl") == .Tcl)
    Swag.assert(Code.detectLanguage("sample.awk") == .Awk)
    Swag.assert(Code.detectLanguage("sample.vim") == .Vim)
    Swag.assert(Code.detectLanguage("sample.tex") == .Latex)
    Swag.assert(Code.detectLanguage("sample.proto") == .Protobuf)
    Swag.assert(Code.detectLanguage("sample.graphql") == .GraphQl)
    Swag.assert(Code.detectLanguage("sample.gradle") == .Gradle)
    Swag.assert(Code.detectLanguage("Makefile") == .Makefile)
    Swag.assert(Code.detectLanguage("Dockerfile") == .Dockerfile)
    Swag.assert(Code.detectLanguage("sample.nix") == .Nix)

    var lexer: Code.GenericLexer
    var host:  Testing.HeadlessHost
    host.setup(640, 180)
    let editor = RichEditCtrl.create(&host.root, {0, 0, 620, 160})
    lexer.configure(.TypeScript)
    editor.setLexer(&lexer)
    editor.setText("export async function answer(): Promise<number> { return 42; } // typed")
    editor.lexAll()

    let content = editor.textAndStyles()
    Swag.assert(content.styles[0] == Code.GenericLexer.Style.Keyword)
    Swag.assert(content.styles[7] == Code.GenericLexer.Style.Keyword)
    Swag.assert(content.styles[13] == Code.GenericLexer.Style.Keyword)
    Swag.assert(content.styles[content.styles.count - 1] == Code.GenericLexer.Style.Comment)

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
        Swag.assert(editor.textAndStyles().styles[0] == Code.GenericLexer.Style.Keyword)
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
    Swag.assert(view.editor.runeAt({0, 0}).style == RichEditLexerSwag.Style.Keyword)
    Swag.assert(view.editor.runeAt({0, 15}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.assert(view.editor.runeAt({0, 23}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(view.editor.runeAt({0, 27}).style == RichEditLexerSwag.Style.Default)
    Swag.assert(view.editor.runeAt({0, 28}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.assert(view.editor.runeAt({0, 40}).style == RichEditLexerSwag.Style.Keyword)
    Swag.assert(view.editor.runeAt({0, 45}).style == RichEditLexerSwag.Style.Control)
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
    Swag.assert(codeStyles[8] == Code.GenericLexer.Style.String)
    Swag.assert(codeStyles[13] == Code.GenericLexer.Style.Function)
    Swag.assert(codeStyles[15] == Code.GenericLexer.Style.Number)
    Swag.assert(codeStyles[20] == Code.GenericLexer.Style.Type)

    var markup: Code.GenericLexer
    markup.configure(.Html)
    editor.setLexer(&markup)
    editor.setText("<a href=\"u\">t</a><!-- c -->")
    editor.lexAll()
    let markupStyles = editor.textAndStyles().styles
    Swag.assert(markupStyles[0] == Code.GenericLexer.Style.Keyword)
    Swag.assert(markupStyles[8] == Code.GenericLexer.Style.String)
    Swag.assert(markupStyles[12] == Code.GenericLexer.Style.Default)
    Swag.assert(markupStyles[17] == Code.GenericLexer.Style.Comment)
}

// The lens as a reader meets it over a code file: opened empty, then typed into, then asked for
// actions with `>`.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-lens-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, swagSampleSource())

    var host: Testing.HeadlessHost
    host.setup(1100, 700)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(1100, 700)
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    for query, i in ["", "doub", ">"]
    {
        window.lens.open(query)
        host.finishAnimations()

        // Typed into, the lens answers first with the lines of the file that hold the query.
        if i == 1
        {
            let first = unwrap window.lens.results.sections[0]
            Swag.assert(first.label == appStrings().lens_InFile and first.count >= 1)
            Swag.assert(Utf8.contains(first.entries[0].title.toString(), "doubled") and first.entries[0].lead.length)
        }

        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, i == 0 ? "showcase.lens.empty" : (i == 1 ? "showcase.lens.query" : "showcase.lens.actions"))
        window.lens.close()
        host.finishAnimations()
    }

    // A colon and a number go to that line.
    window.lens.open(":3")
    host.finishAnimations()
    let goTo = unwrap window.lens.results.sections[0]
    Swag.assert(goTo.label == appStrings().lens_InFile and goTo.entries[0].title == Format.toString(appStrings().lens_GoToLine, 3))
    window.lens.close()
    host.finishAnimations()
}

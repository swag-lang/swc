#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func codeFixturePath(name: string)->String => Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)

// Builds the Swag document the highlighting test lexes.
//
// This one fixture is written at run time instead of being stored under 'datas': the compiler
// collects every '.swg' below 'src' with no exception for a test folder, so a file keeping the
// extension the lexer is selected by would be compiled into the viewer and would publish its
// declarations as part of it.
func swagSampleSource()->String
{
    var result: retval
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
    defer host.shutdown()

    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(Utf8.contains(result.failureReason.toSlice(), Code.texts().err_ZeroByte))
}

// The code zoom value keeps the shared information-band air outside its button frame.
#test
{
    let fileName = codeFixturePath("sample.cpp")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var result = openTestViewer(Code.viewerPlugin(), &host.root, fileName, infoParent: &host.root)
    Swag.assert(result.view != null and result.info != null)
    let view = assume cast(*Code.Panel, result.view)
    assertViewerInfoButton(view.zoomLabel!)
    Swag.assert(result.info.preferredSize.x == ViewerZoomSlotWidth)

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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
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
    defer host.shutdown()
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
    defer host.shutdown()
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
    defer host.shutdown()
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
        {.Html,       "<main>content</main>"},
        {.Assembly,   "MOV eax, ebx ; comment"},
        {.Zig,        "const answer = 42;"},
        {.Nim,        "proc answer(): int = 42"},
        {.Haskell,    "module Answer where"},
        {.Scala,      "class Answer"},
        {.Groovy,     "class Answer"},
        {.Elixir,     "def answer do 42 end"},
        {.Erlang,     "case Value of ok -> true end"},
        {.Clojure,    "defn answer [] 42"},
        {.Julia,      "function answer() 42 end"},
        {.Fortran,    "PROGRAM ANSWER"},
        {.Pascal,     "program Answer;"},
        {.D,          "module answer;"},
        {.ObjectiveC, "@interface Answer"},
        {.Matlab,     "function answer()"},
        {.Tcl,        "proc answer {} { return 42 }"},
        {.Awk,        "BEGIN { print 42 }"},
        {.Vim,        "function Answer()"},
        {.Latex,      "\\section{Answer}"},
        {.Protobuf,   "message Answer {}"},
        {.GraphQl,    "type Answer { value: Int }"},
        {.Gradle,     "class Answer {}"},
        {.Makefile,   "include common.mk"},
        {.Dockerfile, "FROM scratch"},
        {.Nix,        "let answer = 42; in answer"}]

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
    defer host.shutdown()
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

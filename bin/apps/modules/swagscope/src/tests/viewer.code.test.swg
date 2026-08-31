#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func codeFixturePath(name: string)->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)
}

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
    language: CodeLanguage
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

    var result = openTestViewer(codeViewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(Utf8.contains(result.failureReason.toSlice(), "zero byte"))
}

#[Swag.TestTag("golden")]
#test
{
    let source   = swagSampleSource()
    let fileName = Gui.Testing.tempFilePath("scope-code-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let view = CodeViewer.create(&host.root, fileName)
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
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_code_stream_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    var source: String
    for 2_000 do
        source += "func streamedValue()->u32 => 42\n"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = CodeViewer.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()

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
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_code_large_scroll_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    var source: String
    for 90_000 do
        source += "func streamedValue()->u32 => 42\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = CodeViewer.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
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
    Swag.assert(codeLanguage("sample.cpp") == .Cpp)
    Swag.assert(codeLanguage("sample.cs") == .CSharp)
    Swag.assert(codeLanguage("sample.tsx") == .TypeScript)
    Swag.assert(codeLanguage("sample.py") == .Python)
    Swag.assert(codeLanguage("sample.rs") == .Rust)
    Swag.assert(codeLanguage("sample.sql") == .Sql)
    Swag.assert(codeLanguage("sample.yaml") == .Yaml)
    Swag.assert(codeLanguage("sample.csproj") == .Xml)
    Swag.assert(codeLanguage("sample.html") == .Html)
    Swag.assert(codeLanguage("sample.asm") == .Assembly)
    Swag.assert(codeLanguage("sample.zig") == .Zig)
    Swag.assert(codeLanguage("sample.nim") == .Nim)
    Swag.assert(codeLanguage("sample.hs") == .Haskell)
    Swag.assert(codeLanguage("sample.scala") == .Scala)
    Swag.assert(codeLanguage("sample.groovy") == .Groovy)
    Swag.assert(codeLanguage("sample.exs") == .Elixir)
    Swag.assert(codeLanguage("sample.erl") == .Erlang)
    Swag.assert(codeLanguage("sample.clj") == .Clojure)
    Swag.assert(codeLanguage("sample.jl") == .Julia)
    Swag.assert(codeLanguage("sample.f90") == .Fortran)
    Swag.assert(codeLanguage("sample.pas") == .Pascal)
    Swag.assert(codeLanguage("sample.d") == .D)
    Swag.assert(codeLanguage("sample.mm") == .ObjectiveC)
    Swag.assert(codeLanguage("sample.m") == .Matlab)
    Swag.assert(codeLanguage("sample.tcl") == .Tcl)
    Swag.assert(codeLanguage("sample.awk") == .Awk)
    Swag.assert(codeLanguage("sample.vim") == .Vim)
    Swag.assert(codeLanguage("sample.tex") == .Latex)
    Swag.assert(codeLanguage("sample.proto") == .Protobuf)
    Swag.assert(codeLanguage("sample.graphql") == .GraphQl)
    Swag.assert(codeLanguage("sample.gradle") == .Gradle)
    Swag.assert(codeLanguage("Makefile") == .Makefile)
    Swag.assert(codeLanguage("Dockerfile") == .Dockerfile)
    Swag.assert(codeLanguage("sample.nix") == .Nix)

    var lexer: GenericCodeLexer
    var host:  Testing.HeadlessHost
    host.setup(640, 180)
    defer host.shutdown()
    let editor = RichEditCtrl.create(&host.root, {0, 0, 620, 160})
    lexer.configure(.TypeScript)
    editor.setLexer(&lexer)
    editor.setText("export async function answer(): Promise<number> { return 42; } // typed")
    editor.lexAll()

    let content = editor.textAndStyles()
    Swag.assert(content.styles[0] == GenericCodeLexer.Style.Keyword)
    Swag.assert(content.styles[7] == GenericCodeLexer.Style.Keyword)
    Swag.assert(content.styles[13] == GenericCodeLexer.Style.Keyword)
    Swag.assert(content.styles[content.styles.count - 1] == GenericCodeLexer.Style.Comment)

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
        var sampleLexer: GenericCodeLexer
        sampleLexer.configure(sample.language)
        editor.setLexer(&sampleLexer)
        editor.setText(sample.source)
        editor.lexAll()
        Swag.assert(editor.textAndStyles().styles[0] == GenericCodeLexer.Style.Keyword)
    }
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("viewer_code_tokens_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) "readonly value #sanity Swag.safetyPanic #raw do")

    var host: Testing.HeadlessHost
    host.setup(640, 160)
    defer host.shutdown()
    let view = CodeViewer.create(&host.root, fileName)
    view.editor.lexAll()
    Swag.assert(view.editor.runeAt({0, 0}).style == RichEditLexerSwag.Style.Keyword)
    Swag.assert(view.editor.runeAt({0, 15}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.assert(view.editor.runeAt({0, 23}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(view.editor.runeAt({0, 27}).style == RichEditLexerSwag.Style.Default)
    Swag.assert(view.editor.runeAt({0, 28}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.assert(view.editor.runeAt({0, 40}).style == RichEditLexerSwag.Style.Keyword)
    Swag.assert(view.editor.runeAt({0, 45}).style == RichEditLexerSwag.Style.Control)
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

private func codeFixturePath(name: string)->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "files"), name)
}

private struct CodeLanguageSample
{
    language: CodeLanguage
    source:   string
}

#test
{
    let fileName = codeFixturePath("sample.swg")
    let source   = expect File.readAllText(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let view = CodePluginView.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    view.editor.lexAll()

    let content = view.editor.textAndStyles()
    var expected: Array'rune
    for value in source.toRuneArray() where value != '\r' do
        expected.add(value)

    // RichEdit stores logical line breaks as LF; a Windows checkout gives the fixture CRLF.
    @assert(Utf8.fromUnicode(content.text.toSlice()) == Utf8.fromUnicode(expected.toSlice()))
    var colored: bool
    for style in content.styles where style != 0
    {
        colored = true
        break
    }

    @assert(colored)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "plugin.code.document")
}

// End opens a bounded tail window instead of materializing every preceding byte.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("filescope_code_stream_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    var source: String
    for 2_000 do
        source += "func streamedValue()->u32 => 42\n"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = CodePluginView.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()

    let beforeEnd = view.editor.scrollPosition()
    var end       = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    @assert(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    @assert(view.editor.scrollPosition().y > beforeEnd.y)
}

// Keeps the code viewer's estimated document extent from shrinking while multiple chunks are
// appended without an intervening paint, while the focused editor honors every navigation tier.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("filescope_code_large_scroll_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    var source: String
    for 90_000 do
        source += "func streamedValue()->u32 => 42\n"
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = CodePluginView.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    discard host.render(view)
    view.updateEstimatedHeight()

    view.setInitialFocus(view.editor)
    @assert(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    @assert(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    @assert(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    @assert(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    @assert(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    @assert(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 8
    {
        view.loadNextChunk()
        @assert(view.virtualHeight >= firstVirtualHeight)
        @assert(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    host.keyPress(Input.Key.End)
    discard host.render(view)
    @assert(view.residentStart > 0)
    @assert(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    @assert(view.residentStart == 0)
    @assert(view.editor.selectionEnd().lineIndex == 0)
    @assert(view.editor.scrollPosition().y == 0)
}

#test
{
    @assert(File.exists(codeFixturePath("sample.swg")))
    @assert(File.exists(codeFixturePath("sample.cpp")))
    @assert(File.exists(codeFixturePath("sample.json")))
    @assert(codeLanguage("sample.cpp") == .Cpp)
    @assert(codeLanguage("sample.cs") == .CSharp)
    @assert(codeLanguage("sample.tsx") == .TypeScript)
    @assert(codeLanguage("sample.py") == .Python)
    @assert(codeLanguage("sample.rs") == .Rust)
    @assert(codeLanguage("sample.sql") == .Sql)
    @assert(codeLanguage("sample.yaml") == .Yaml)
    @assert(codeLanguage("sample.csproj") == .Xml)
    @assert(codeLanguage("sample.html") == .Html)
    @assert(codeLanguage("sample.asm") == .Assembly)
    @assert(codeLanguage("sample.zig") == .Zig)
    @assert(codeLanguage("sample.nim") == .Nim)
    @assert(codeLanguage("sample.hs") == .Haskell)
    @assert(codeLanguage("sample.scala") == .Scala)
    @assert(codeLanguage("sample.groovy") == .Groovy)
    @assert(codeLanguage("sample.exs") == .Elixir)
    @assert(codeLanguage("sample.erl") == .Erlang)
    @assert(codeLanguage("sample.clj") == .Clojure)
    @assert(codeLanguage("sample.jl") == .Julia)
    @assert(codeLanguage("sample.f90") == .Fortran)
    @assert(codeLanguage("sample.pas") == .Pascal)
    @assert(codeLanguage("sample.d") == .D)
    @assert(codeLanguage("sample.mm") == .ObjectiveC)
    @assert(codeLanguage("sample.m") == .Matlab)
    @assert(codeLanguage("sample.tcl") == .Tcl)
    @assert(codeLanguage("sample.awk") == .Awk)
    @assert(codeLanguage("sample.vim") == .Vim)
    @assert(codeLanguage("sample.tex") == .Latex)
    @assert(codeLanguage("sample.proto") == .Protobuf)
    @assert(codeLanguage("sample.graphql") == .GraphQl)
    @assert(codeLanguage("sample.gradle") == .Gradle)
    @assert(codeLanguage("Makefile") == .Makefile)
    @assert(codeLanguage("Dockerfile") == .Dockerfile)
    @assert(codeLanguage("sample.nix") == .Nix)

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
    @assert(content.styles[0] == GenericCodeLexer.Style.Keyword)
    @assert(content.styles[7] == GenericCodeLexer.Style.Keyword)
    @assert(content.styles[13] == GenericCodeLexer.Style.Keyword)
    @assert(content.styles[content.styles.count - 1] == GenericCodeLexer.Style.Comment)

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
        @assert(editor.textAndStyles().styles[0] == GenericCodeLexer.Style.Keyword)
    }
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("plugin_code_tokens_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) "readonly value #sanity @safetypanic #raw do")

    var host: Testing.HeadlessHost
    host.setup(640, 160)
    defer host.shutdown()
    let view = CodePluginView.create(&host.root, fileName)
    view.editor.lexAll()
    @assert(view.editor.runeAt({0, 0}).style == RichEditLexerSwag.Style.Keyword)
    @assert(view.editor.runeAt({0, 15}).style == RichEditLexerSwag.Style.Intrinsic)
    @assert(view.editor.runeAt({0, 23}).style == RichEditLexerSwag.Style.Intrinsic)
    @assert(view.editor.runeAt({0, 36}).style == RichEditLexerSwag.Style.Keyword)
    @assert(view.editor.runeAt({0, 41}).style == RichEditLexerSwag.Style.Control)
}

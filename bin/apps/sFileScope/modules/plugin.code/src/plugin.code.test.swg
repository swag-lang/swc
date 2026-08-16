#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("filescope_code_%.swg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) "func answer()->u32 => 42\n")

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
    @assert(Utf8.fromUnicode(content.text.toSlice()) == "func answer()->u32 => 42\n")
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
    var end = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    @assert(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    @assert(view.editor.scrollPosition().y > beforeEnd.y)
}

#test
{
    @assert(codeLanguage("sample.cpp") == .Cpp)
    @assert(codeLanguage("sample.cs") == .CSharp)
    @assert(codeLanguage("sample.tsx") == .TypeScript)
    @assert(codeLanguage("sample.py") == .Python)
    @assert(codeLanguage("sample.rs") == .Rust)
    @assert(codeLanguage("sample.sql") == .Sql)
    @assert(codeLanguage("sample.yaml") == .Yaml)
    @assert(codeLanguage("sample.csproj") == .Xml)

    var lexer: GenericCodeLexer
    var host: Testing.HeadlessHost
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

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    @assert(textRenderKind("notes.txt") == TextRenderKind.Plain)
    @assert(textRenderKind("README.MD") == TextRenderKind.Markdown)
    @assert(textRenderKind("page.html") == TextRenderKind.Html)
    @assert(textRenderKind("main.cpp") == TextRenderKind.Code)
    @assert(textRenderKind("header.hpp") == TextRenderKind.Code)
    @assert(textRenderKind("program.cs") == TextRenderKind.Code)
    @assert(textRenderKind("App.java") == TextRenderKind.Code)
    @assert(textRenderKind("client.js") == TextRenderKind.Code)
    @assert(textRenderKind("component.tsx") == TextRenderKind.Code)
    @assert(textRenderKind("data.json") == TextRenderKind.Code)
    @assert(textRenderKind("script.py") == TextRenderKind.Code)
    @assert(textRenderKind("lib.rs") == TextRenderKind.Code)
    @assert(textRenderKind("server.go") == TextRenderKind.Code)
    @assert(textRenderKind("layout.xml") == TextRenderKind.Code)
    @assert(textRenderKind("theme.css") == TextRenderKind.Code)
    @assert(textRenderKind("query.sql") == TextRenderKind.Code)
    @assert(textRenderKind("build.sh") == TextRenderKind.Code)
    @assert(textRenderKind("setup.ps1") == TextRenderKind.Code)
    @assert(textRenderKind("module.lua") == TextRenderKind.Code)
    @assert(textRenderKind("tool.rb") == TextRenderKind.Code)
    @assert(textRenderKind("index.php") == TextRenderKind.Code)
    @assert(textRenderKind("boot.asm") == TextRenderKind.Code)
    @assert(textRenderKind("build.bat") == TextRenderKind.Code)
    @assert(textRenderKind("settings.toml") == TextRenderKind.Code)
    @assert(textRenderKind("pipeline.yaml") == TextRenderKind.Code)
    @assert(textRenderKind("module.swg") == TextRenderKind.Code)
    @assert(textRenderKind("unknown.bin") == TextRenderKind.None)
}

#test
{
    let markdown = MarkdownTextRenderer.render("Title\n=====\n\nA wrapped\nparagraph with __weight__, _emphasis_ and &copy;.\n\n1. first\n2. [x] shipped\n   - nested\n\n| Name | State |\n|:-----|------:|\n| HTML | ready |\n\n> note\n\n```cpp\nif (ready)\n```\n![logo](logo.png) and [site](https://example.com)")
    @assert(Utf8.contains(markdown.toSlice(), "<p1><b>Title</b></p>"))
    @assert(Utf8.contains(markdown.toSlice(), "A wrapped paragraph with <b>weight</b>, <i>emphasis</i> and ©."))
    @assert(Utf8.contains(markdown.toSlice(), "<p3>1.</p> first"))
    @assert(Utf8.contains(markdown.toSlice(), "<p1>[x]</p> shipped"))
    @assert(Utf8.contains(markdown.toSlice(), "<b>Name</b>  <p3>|</p>  <b>State</b>"))
    @assert(Utf8.contains(markdown.toSlice(), "<p3>></p> <i>note</i>"))
    @assert(Utf8.contains(markdown.toSlice(), "<p2>"))
    @assert(Utf8.contains(markdown.toSlice(), "[Image: logo]"))
    @assert(Utf8.contains(markdown.toSlice(), "<u>site</u> (<url>https://example.com</url>)"))
}

#test
{
    let html = HtmlTextRenderer.render("<!doctype html><head><title>Hidden</title></head><style>.hidden{}</style><script>alert(1)</script><main><h1 class=\"hero\">Title</h1><p>  Hello   &amp; &#x1F30D;<br>world </p><ol><li>one</li><li>two<ul><li>nested</li></ul></li></ol><p><input type=\"checkbox\" checked> done</p><p><a href=\"https://example.com?a=1&amp;b=2\">Site</a> <img src=\"logo.png\" alt=\"Logo\"></p><table><caption>Builds</caption><tr><th>Name</th><th>State</th></tr><tr><td>HTML</td><td>ready</td></tr></table></main>")
    @assert(!Utf8.contains(html.toSlice(), "Hidden"))
    @assert(!Utf8.contains(html.toSlice(), "alert"))
    @assert(Utf8.contains(html.toSlice(), "<p1><b>Title</b></p>"))
    @assert(Utf8.contains(html.toSlice(), "Hello & 🌍\nworld"))
    @assert(Utf8.contains(html.toSlice(), "<p3>1.</p> one"))
    @assert(Utf8.contains(html.toSlice(), "<p1>•</p> nested"))
    @assert(Utf8.contains(html.toSlice(), "[x] done"))
    @assert(Utf8.contains(html.toSlice(), "<u>Site</u> (<url>https://example.com?a=1&b=2</url>)"))
    @assert(Utf8.contains(html.toSlice(), "[Image: Logo]"))
    @assert(Utf8.contains(html.toSlice(), "<b>Name</b>  <p3>|</p>  <b>State</b>"))
}

#test
{
    let markdown = MarkdownTextRenderer.render("Literal <b>tag</b>, escaped \\*star\\*, snake_case_name and <https://example.com>.")
    @assert(Utf8.contains(markdown.toSlice(), "Literal ‹b›tag‹/b›, escaped *star*, snake_case_name"))
    @assert(Utf8.contains(markdown.toSlice(), "<url>https://example.com</url>"))

    let html = HtmlTextRenderer.render("<p>&lt;b&gt;safe&lt;/b&gt; &#169; &#x2014; &unknown;</p><pre>  exact\n  space</pre><!-- hidden")
    @assert(Utf8.contains(html.toSlice(), "‹b›safe‹/b› © — &unknown;"))
    @assert(Utf8.contains(html.toSlice(), "<p2>  exact\n  space</p>"))
}

#test
{
    @assert(textCodeLanguage("main.cpp") == TextCodeLanguage.Cpp)
    @assert(textCodeLanguage("app.tsx") == TextCodeLanguage.TypeScript)
    @assert(textCodeLanguage("settings.yaml") == TextCodeLanguage.Config)
    @assert(textCodeLanguage("README.md") == TextCodeLanguage.None)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 620)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 900, 40})
    let markdown = TextPluginView.createLoaded(&host.root, commands, "README.md", "# Visible title\n\nRendered paragraph.", true)
    markdown.resize(900, 580)
    markdown.applyLayout()
    @assert(markdown.kind == .Markdown)
    @assert(markdown.showingRendered)
    @assert(markdown.renderLabel.name.raw == "Visible title\n\nRendered paragraph." or @countof(markdown.renderLabel.name.raw) > 0)
    @assert(markdown.commands.parent == commands)
    markdown.showRendered(false)
    @assert(markdown.sourceEdit.text() == "# Visible title\n\nRendered paragraph.")
    markdown.showRendered(true)

    let code = TextPluginView.createLoaded(&host.root, commands, "main.cpp", "int main() { return 0; }", true)
    code.resize(900, 580)
    code.applyLayout()
    @assert(code.kind == .Code)
    @assert(!code.wrapping)
    @assert(code.sourceEdit.lexer != null)
    @assert(!code.showingRendered)
    let styled = code.sourceEdit.textAndStyles()
    @assert(styled.styles[0] == cast(u8) TextCodeLexer.Style.Type)
    @assert(styled.styles[4] == cast(u8) TextCodeLexer.Style.Function)
    @assert(styled.styles[13] == cast(u8) TextCodeLexer.Style.Control)
    Testing.assertContentFits(code)

    let python = TextPluginView.createLoaded(&host.root, commands, "script.py", "def greet(name):\n    # note\n    return \"hi\"", true)
    let pythonStyles = python.sourceEdit.textAndStyles()
    @assert(pythonStyles.styles[0] == cast(u8) TextCodeLexer.Style.Keyword)
    @assert(pythonStyles.styles[21] == cast(u8) TextCodeLexer.Style.Comment)

    let json = TextPluginView.createLoaded(&host.root, commands, "data.json", "{\"name\": 12, \"ready\": true}", true)
    let jsonStyles = json.sourceEdit.textAndStyles()
    @assert(jsonStyles.styles[2] == cast(u8) TextCodeLexer.Style.Property)

    let sql = TextPluginView.createLoaded(&host.root, commands, "query.sql", "SELECT name FROM people WHERE id = 7", true)
    let sqlStyles = sql.sourceEdit.textAndStyles()
    @assert(sqlStyles.styles[0] == cast(u8) TextCodeLexer.Style.Keyword)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 620)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 900, 40})
    let html = TextPluginView.createLoaded(&host.root, commands, "page.html", "<h1>Hello</h1><p>World</p>", true)
    html.resize(900, 580)
    html.applyLayout()
    @assert(html.kind == .Html and html.showingRendered)
    html.showRendered(false)
    @assert(html.sourceEdit.lexer != null)
    @assert(html.sourceEdit.text() == "<h1>Hello</h1><p>World</p>")
    let htmlStyles = html.sourceEdit.textAndStyles()
    @assert(htmlStyles.styles[0] == cast(u8) TextCodeLexer.Style.Preprocessor)
    @assert(htmlStyles.styles[1] == cast(u8) TextCodeLexer.Style.Type)

    let plain = TextPluginView.createLoaded(&host.root, commands, "notes.txt", "first\nsecond", true)
    plain.resize(900, 580)
    plain.applyLayout()
    @assert(plain.kind == .Plain and !plain.showingRendered)
    @assert(plain.sourceEdit.lexer == null)
    @assert(plain.sourceEdit.text() == "first\nsecond")
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let bar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    bar.dockStyle       = .Top
    bar.backgroundStyle = .Window
    bar.padding         = {8, 4, 8, 4}
    let code = TextPluginView.createLoaded(&host.root, bar, "sample.cpp", "#include <vector>\n\nstruct Sample\n{\n    int value = 42;\n\n    bool ready() const\n    {\n        // Fast read-only preview.\n        return value > 0;\n    }\n};", true)
    code.dockStyle         = .Center
    code.commands.dockStyle = .Right
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "sviewer.text.code")
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let bar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    bar.dockStyle       = .Top
    bar.backgroundStyle = .Window
    bar.padding         = {8, 4, 8, 4}
    let markdown = TextPluginView.createLoaded(&host.root, bar, "README.md", "# Universal viewer\n\nA **fast** preview with `inline code`, proper wrapped\nparagraphs and useful document structure.\n\n- [x] Drop a file\n- Read without distractions\n\n| Renderer | Mode |\n|----------|------|\n| Markdown | Safe |\n\n> Plugins load only when needed.", true)
    markdown.dockStyle          = .Center
    markdown.commands.dockStyle = .Right
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "sviewer.text.markdown")
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let bar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    bar.dockStyle       = .Top
    bar.backgroundStyle = .Window
    bar.padding         = {8, 4, 8, 4}
    let html = TextPluginView.createLoaded(&host.root, bar, "sample.html", "<head><style>body{display:none}</style></head><main><h1>Safe HTML preview</h1><p>Semantic <strong>content</strong> is visible, with normalized whitespace.</p><ol><li>Scripts never run</li><li><a href=\"https://swag-lang.org\">Links stay explicit</a></li></ol><table><tr><th>Format</th><th>Mode</th></tr><tr><td>HTML</td><td>Offline</td></tr></table></main>", true)
    html.dockStyle          = .Center
    html.commands.dockStyle = .Right
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "sviewer.text.html")
}

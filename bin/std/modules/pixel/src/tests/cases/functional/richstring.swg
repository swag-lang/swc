#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Text given by assignment, `set` or `append` is literal: nothing in it is read as markup.
#test
{
    var text: RichString = "<b>a</b> &amp; <a>b</a>"
    Swag.require(text.isPlain())
    Swag.require(text.text == "<b>a</b> &amp; <a>b</a>")

    text.compute()
    Swag.require(not text.hasUrl)
    for &chunk in text.chunks do
        Swag.require(not chunk.hasFontStyle and not chunk.isUrl)

    text.set("<i>x</i>", {bold: true})
    text.append("<u>y</u>")
    Swag.require(text.text == "<i>x</i><u>y</u>")

    text.compute()
    Swag.require(text.chunks.count == 2)
    Swag.require(text.chunks[0].slice == "<i>x</i>")
    Swag.require(text.chunks[0].fontStyle == .Bold)
    Swag.require(not text.chunks[1].hasFontStyle)
    Swag.require(text.chunks[1].under == .None)
}

// A CRLF pair remains one line break when its bytes belong to different style runs.
#test
{
    var text = RichString.fromMarkup("<b>A\r</b>\nB")
    text.compute()

    var eolCount = 0
    for &chunk in text.chunks where chunk.isEol do
        eolCount += 1
    Swag.require(eolCount == 1)
}

// Typed runs carry each style, and a link reports its text or the target it names.
#test
{
    var text: RichString
    text.append("plain ")
    text.append("both", {bold: true, italic: true})
    text.append(" ")
    text.append("ink", {underline: .Underline, paletteIndex: 2})
    text.append(" ")
    text.appendLink("here")
    text.append(" ")
    text.appendLink("docs", "https://example.com/docs", {italic: true})
    Swag.require(text.text == "plain both ink here docs")
    Swag.require(not text.isPlain())

    text.compute()
    Swag.require(text.hasUrl)
    Swag.require(text.chunks.count == 9)
    Swag.require(not text.chunks[0].hasFontStyle)
    Swag.require(text.chunks[2].fontStyle == .BoldItalic)
    Swag.require(text.chunks[4].under == .Underline)
    Swag.require(text.chunks[4].colorIdx == 2)
    Swag.require(text.chunks[6].isUrl and not text.chunks[6].hasFontStyle)
    Swag.require(text.chunks[8].isUrl and text.chunks[8].fontStyle == .Italic)
    Swag.require(text.chunks[6].urlStart != text.chunks[8].urlStart)

    Swag.require(text.urlText(text.chunks[6].urlStart) == "here")
    Swag.require(text.urlTarget(text.chunks[6].urlStart) == "here")
    Swag.require(text.urlText(text.chunks[8].urlStart) == "docs")
    Swag.require(text.urlTarget(text.chunks[8].urlStart) == "https://example.com/docs")
    Swag.require(text.urlTarget(Swag.U64.Max).isEmpty())

    // A copy keeps the runs and rebuilds its own chunks.
    var copy = text
    copy.compute()
    Swag.require(copy.chunks.count == 9)
    Swag.require(copy.chunks[2].fontStyle == .BoldItalic)
    Swag.require(copy.urlTarget(copy.chunks[8].urlStart) == "https://example.com/docs")

    text.clear()
    text.compute()
    Swag.require(text.isEmpty() and text.isPlain() and text.chunks.isEmpty())
}

// Markup is a strict subset of inline HTML; what it does not name stays literal.
#test
{
    var text = RichString.fromMarkup("a <b>b <i>c</i></b> <u>d</u> <span class=\"p3\">e</span><br>&lt;f&gt; &amp; &quot;g&quot;&nbsp;&apos;")
    Swag.require(text.text == "a b c d e\n<f> & \"g\" '")

    text.compute()
    Swag.require(text.chunks[2].fontStyle == .Bold)
    Swag.require(text.chunks[4].fontStyle == .BoldItalic)
    Swag.require(text.chunks[6].under == .Underline)
    Swag.require(text.chunks[8].colorIdx == 3)
    Swag.require(text.chunks[9].isEol)

    // Unknown elements and entities, and a malformed link, are text.
    text.setMarkup("<p1>x</p> <em>y</em> &copy; <a href=\"z")
    Swag.require(text.isPlain())
    Swag.require(text.text == "<p1>x</p> <em>y</em> &copy; <a href=\"z")

    // An element left open runs to the end; a stray closing element changes nothing.
    text.setMarkup("</b>a <b>b")
    text.compute()
    Swag.require(text.text == "a b")
    Swag.require(not text.chunks[0].hasFontStyle)
    Swag.require(text.chunks[2].fontStyle == .Bold)

    text.setMarkup("<a href=\"cmd:retry\">Retry</a> or <a>wait</a>")
    text.compute()
    Swag.require(text.urlText(text.chunks[0].urlStart) == "Retry")
    Swag.require(text.urlTarget(text.chunks[0].urlStart) == "cmd:retry")
    Swag.require(text.urlTarget(text.chunks[4].urlStart) == "wait")

    text.setMarkup(null)
    Swag.require(text.isEmpty() and text.isPlain())
}

// Escaped text reads back unchanged from a markup sentence, and `plainText` strips the markup.
#test
{
    let outside = "<b>R&D</b> <a href=\"x\">.txt"
    let escaped = RichString.escape(outside)
    Swag.require(escaped == "&lt;b&gt;R&amp;D&lt;/b&gt; &lt;a href=\"x\"&gt;.txt")

    let sentence = Format.toString("<i>%</i> already exists.", escaped)
    var text     = RichString.fromMarkup(sentence)
    Swag.require(text.text == "<b>R&D</b> <a href=\"x\">.txt already exists.")

    text.compute()
    Swag.require(text.chunks[0].fontStyle == .Italic)
    Swag.require(not text.hasUrl)

    Swag.require(RichString.plainText(sentence) == text.text)
    Swag.require(RichString.plainText("<b>Bold</b> &amp; <a href=\"t\">link</a>") == "Bold & link")
}

// A line break that follows a space still ends the line, in plain text and inside a styled run.
#test
{
    var text: RichString = "a \nb"
    text.compute()
    Swag.require(text.chunks.count == 4)
    Swag.require(text.chunks[1].isSpace and text.chunks[1].slice == " ")
    Swag.require(text.chunks[2].isEol)
    Swag.require(text.chunks[3].slice == "b")

    text.setMarkup("<b>a \r\nb</b>")
    text.compute()
    Swag.require(text.chunks.count == 4)
    Swag.require(text.chunks[2].isEol and text.chunks[2].slice == "\r\n")
    Swag.require(text.chunks[3].fontStyle == .Bold)
}

// Setting the plain text a string already holds keeps its chunks; any other change rebuilds them.
#test
{
    var text: RichString = "same"
    text.compute()
    let chunk = &text.chunks[0]
    chunk.visible = true

    text.set("same")
    text.compute()
    Swag.require(text.chunks[0].visible)

    text.set("same", {bold: true})
    text.compute()
    Swag.require(text.chunks[0].fontStyle == .Bold)

    text.set("same")
    text.compute()
    Swag.require(text.isPlain())
    Swag.require(not text.chunks[0].hasFontStyle)
}

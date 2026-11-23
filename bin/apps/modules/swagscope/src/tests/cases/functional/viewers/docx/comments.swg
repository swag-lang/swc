#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Classic comment prose and author names are parsed as text, not trusted markup.
#test
{
    let comments = expect Docx.CommentCatalog.parse("""<w:comments>
        <w:comment w:id="1" w:author="R&amp;D &lt;Team&gt;"><w:p><w:r><w:t>First &lt;comment&gt; &amp; safe.</w:t></w:r></w:p>
            <w:p><w:r><w:t>More.</w:t></w:r></w:p></w:comment>
        <w:comment w:id="2" w:author="Équipe &lt;R&amp;D&gt;"><w:p><w:r><w:t>Second comment.</w:t></w:r></w:p></w:comment>
    </w:comments>""")
    let first    = comments.lookup("1")
    let second   = comments.lookup("2")
    Swag.require(first.found and first.author == "R&D <Team>")
    Swag.require(first.html == "<p>First &lt;comment&gt; &amp; safe.</p><p>More.</p>")
    Swag.require(second.found and second.author == "Équipe <R&D>" and second.html == "<p>Second comment.</p>")
    Swag.require(not comments.lookup("9").found)
}

// Invalid roots, duplicate IDs and negative comment IDs are rejected.
#test
{
    var rootError: Swag.Error
    discard catch Docx.CommentCatalog.parse("<document/>") as rootError
    Swag.require(rootError.value() is Errors.InvalidFormatError)

    var duplicateError: Swag.Error
    discard catch Docx.CommentCatalog.parse("<comments><comment id=\"1\"/><comment id=\"1\"/></comments>") as duplicateError
    Swag.require(duplicateError.value() is Errors.InvalidFormatError)

    var negativeError: Swag.Error
    discard catch Docx.CommentCatalog.parse("<comments><comment id=\"-1\"/></comments>") as negativeError
    Swag.require(negativeError.value() is Errors.InvalidFormatError)
}

// Referenced comments appear once in first-reference order, with escaped authors and text.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.comments.docx"))
    Swag.require(Utf8.contains(document.html, "Opening <a id=\"docx-comment-range-2\"></a> second span <sup class=\"docx-comment-reference\"><a href=\"#docx-comment-2\">2</a></sup> middle <a id=\"docx-comment-range-1\"></a> first span <sup class=\"docx-comment-reference\"><a href=\"#docx-comment-1\">1</a></sup>"))
    Swag.require(Utf8.contains(document.html, "repeated <sup class=\"docx-comment-reference\"><a href=\"#docx-comment-2\">2</a></sup> missing [Comment not shown]"))
    Swag.require(Utf8.contains(document.html, "<section class=\"docx-comments\"><h2>Comments</h2><div id=\"docx-comment-2\"><p class=\"docx-comment-author\"><strong>Équipe &lt;R&amp;D&gt;</strong></p><p>Second comment.</p><p><a href=\"#docx-comment-range-2\">Return to comment range</a></p></div>"), document.html)
    Swag.require(Utf8.contains(document.html, "<strong>R&amp;D &lt;Team&gt;</strong></p><p>First &lt;comment&gt; &amp; safe.</p><p>More.</p><p><a href=\"#docx-comment-range-1\">Return to comment range</a></p></div></section>"))
    Swag.require(document.commentsSimplified)
    Swag.require(Utf8.contains(document.details(), "comment ranges and placement simplified"))
}

// A damaged optional comments part leaves body text readable and marks unresolved references.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.bad-comments.docx"))
    Swag.require(Utf8.contains(document.html, "Opening [Comment not shown]"))
    Swag.require(document.commentsSimplified)
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Paragraph section properties belong to the paragraph just finished and carry that section's page box.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.sections.docx"))
    let html     = document.html
    Swag.require(Utf8.contains(html, "<p>First section</p><hr><p>Continuous section</p><p>Final section</p>"), html)
    Swag.require(document.pageWidth == 9360 and document.pageHeight == 12960)
    Swag.require(document.marginTop == 360 and
                 document.marginRight == 540 and
                 document.marginBottom == 360 and
                 document.marginLeft == 540)
    Swag.require(not document.stylesSimplified and document.sectionLayoutSimplified)
    Swag.require(Utf8.contains(document.details(), Docx.texts().ui_SectionLayoutSimplified))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// A valid authored page size and inset map to a bounded CSS reading surface.
#test
{
    var styles: Odf.StyleCatalog
    expect styles.read("<styles><page-layout-properties page-width='8.27in' margin-top='0.8in' margin-bottom='0.5in' margin-left='2cm' margin-right='2cm'/></styles>")
    Swag.require(styles.page.valid and not styles.page.limited)
    Swag.require(Math.abs(styles.page.pageWidthCssPixels() - 794) < 1)
    Swag.require(styles.page.cssInsets() == "77px 76px 48px 76px")
}

// Multiple or out-of-range page layouts disclose approximation and keep safe defaults.
#test
{
    var multiple: Odf.StyleCatalog
    expect multiple.read("<styles><page-layout-properties page-width='8in'/><page-layout-properties page-width='11in'/></styles>")
    Swag.require(multiple.page.valid and multiple.page.limited and multiple.page.width == 576)

    var invalid: Odf.StyleCatalog
    expect invalid.read("<styles><page-layout-properties page-width='99999pt'/></styles>")
    Swag.require(not invalid.page.valid and invalid.page.limited)
    Swag.require(invalid.page.pageWidthCssPixels() == 680 and invalid.page.cssInsets() == "24px")
}

// Relative ODF styles compose absolutely; normal and zero explicitly reset inherited properties.
#test
{
    var styles: Odf.StyleCatalog
    expect styles.read("""<styles><default-style family="paragraph"><text-properties font-size="14pt"/><paragraph-properties margin-top="12pt" line-height="150%"/></default-style>
    <style name="Title" family="paragraph"><text-properties font-size="150%" font-weight="bold" color="#216a56"/></style>
    <style name="Quiet" family="paragraph" parent-style-name="Title"><text-properties font-weight="normal"/><paragraph-properties margin-top="0pt" line-height="normal"/></style>
    <style name="Small" family="text"><text-properties font-size="50%" font-style="italic"/></style></styles>""")
    styles.finish()
    let title = styles.lookup("Title", .Paragraph)
    Swag.require(title.run.size == 42 and title.run.bold == .On and title.run.color == "216a56")
    let quiet = styles.lookup("Quiet", .Paragraph)
    Swag.require(quiet.run.size == 42 and quiet.run.bold == .Off and quiet.paragraph.before == 0)
    Swag.require(quiet.paragraph.line == 240 and quiet.paragraph.lineRule == "auto")
    var run   = quiet.run
    let small = styles.lookup("Small", .Text)
    small.applyRun(&run)
    Swag.require(run.size == 21 and run.italic == .On)
}

// Missing parents and cycles preserve available text formatting and disclose the approximation.
#test
{
    var styles: Odf.StyleCatalog
    expect styles.read("""<styles><style name="A" family="paragraph" parent-style-name="B"><text-properties font-size="18pt"/></style><style name="B" family="paragraph" parent-style-name="A"/><style name="Missing" family="paragraph" parent-style-name="Absent"><text-properties font-style="italic"/></style></styles>""")
    styles.finish()
    let cycle   = styles.lookup("A", .Paragraph)
    let missing = styles.lookup("Missing", .Paragraph)
    Swag.require(cycle.limited and cycle.run.size == 36)
    Swag.require(missing.limited and missing.run.italic == .On)
}

// Unit conversion and style validation keep physical measurements bounded and CSS literal.
#test
{
    let inch = Odf.points("1in")
    let cm   = Odf.points("2.54cm")
    Swag.require(inch.valid and cm.valid and Math.abs(inch.value - cm.value) < 0.001)
    Swag.require(Odf.points("0").valid and not Odf.points("99999pt").valid)
    Swag.require(Odf.fontFamily("'Liberation Sans'") == "Liberation Sans")
    Swag.require(Odf.fontFamily("Bad';position:absolute").isEmpty())
    Swag.require(Odf.rgb("#216a56") == "216a56" and Odf.rgb("red;display:none").isEmpty())
}

// Content automatic styles override a common name without losing its named parent's defaults.
#test
{
    var styles: Odf.StyleCatalog
    expect styles.read("<styles><style name='Base' family='paragraph'><text-properties font-size='12pt' font-weight='bold'/></style><style name='P1' family='paragraph' parent-style-name='Base'><text-properties color='#112233'/></style></styles>")
    expect styles.read("<automatic-styles><style name='P1' family='paragraph' parent-style-name='Base'><text-properties color='#216a56' font-weight='normal'/></style></automatic-styles>")
    styles.finish()
    let automatic = styles.lookup("P1", .Paragraph)
    Swag.require(automatic.run.size == 24 and automatic.run.bold == .Off and automatic.run.color == "216a56")
    Swag.require(not automatic.limited)
}

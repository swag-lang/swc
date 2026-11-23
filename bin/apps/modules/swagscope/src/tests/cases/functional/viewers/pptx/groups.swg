#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// One unrotated group applies its scale and translation to each child shape.
#test
{
    var theme = Pptx.SlideTheme.defaults()
    var images: Package.ImageCatalog
    let page = expect Pptx.SlidePage.parse("""
        <p:sld><p:spTree><p:grpSp>
          <p:nvGrpSpPr><p:cNvPr id="1" name="Group"/></p:nvGrpSpPr>
          <p:grpSpPr><a:xfrm><a:off x="952500" y="1905000"/><a:ext cx="3810000" cy="1905000"/><a:chOff x="95250" y="190500"/><a:chExt cx="1905000" cy="952500"/></a:xfrm></p:grpSpPr>
          <p:sp><p:nvSpPr><p:cNvPr id="2" name="Child"/></p:nvSpPr><p:spPr>
            <a:xfrm><a:off x="190500" y="285750"/><a:ext cx="381000" cy="190500"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
            <a:solidFill><a:srgbClr val="336699"/></a:solidFill>
          </p:spPr><p:txBody><a:p><a:r><a:rPr sz="1800"/><a:t>Grouped label</a:t></a:r></a:p></p:txBody></p:sp>
        </p:grpSp></p:spTree></p:sld>
        """, &theme, &images)

    Swag.require(not page.simplified and page.shapes.count == 1)
    Swag.require(page.shapes[0].bounds == Math.Rectangle{120, 220, 80, 40})
    Swag.require(Utf8.contains(page.canvasHtml(960, 720), "left:12.5000%"))
    Swag.require(Utf8.contains(page.shapes[0].html, "font-size:5.0000vw"))
    Swag.require(Utf8.contains(page.readingHtml(), "Grouped label"))
}

#test
{
    var theme = Pptx.SlideTheme.defaults()
    var images: Package.ImageCatalog
    let rotated = expect Pptx.SlidePage.parse("""
        <p:sld><p:spTree><p:grpSp><p:grpSpPr>
          <a:xfrm rot="5400000"><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/><a:chOff x="0" y="0"/><a:chExt cx="952500" cy="952500"/></a:xfrm>
        </p:grpSpPr><p:sp><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr><p:txBody><a:p><a:r><a:t>Rotated text stays readable</a:t></a:r></a:p></p:txBody></p:sp></p:grpSp></p:spTree></p:sld>
        """, &theme, &images)
    let nested = expect Pptx.SlidePage.parse("""
        <p:sld><p:spTree><p:grpSp><p:grpSpPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/><a:chOff x="0" y="0"/><a:chExt cx="952500" cy="952500"/></a:xfrm>
        </p:grpSpPr><p:grpSp><p:grpSpPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/><a:chOff x="0" y="0"/><a:chExt cx="952500" cy="952500"/></a:xfrm>
        </p:grpSpPr><p:sp><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr></p:sp></p:grpSp></p:grpSp></p:spTree></p:sld>
        """, &theme, &images)

    Swag.require(rotated.simplified and nested.simplified)
    Swag.require(Utf8.contains(rotated.readingHtml(), "Rotated text stays readable"))
    let fallback = rotated.canvasHtml(960, 720)
    Swag.require(Utf8.contains(fallback, "Rotated text stays readable"))
    Swag.require(not Utf8.contains(fallback, "position:absolute"))
}

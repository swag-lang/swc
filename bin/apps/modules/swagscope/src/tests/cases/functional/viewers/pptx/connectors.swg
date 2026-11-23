#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Simple DrawingML connectors render as bounded strokes across horizontal, vertical, and diagonal orientations.
#test
{
    var theme = Pptx.SlideTheme.defaults()
    let page = expect Pptx.SlidePage.parse("""
        <p:sld><p:spTree>
          <p:cxnSp><p:nvCxnSpPr><p:cNvPr id="1" name="Horizontal"/></p:nvCxnSpPr><p:spPr>
            <a:xfrm><a:off x="95250" y="190500"/><a:ext cx="952500" cy="0"/></a:xfrm>
            <a:prstGeom prst="line"><a:avLst/></a:prstGeom>
            <a:ln w="19050"><a:solidFill><a:srgbClr val="336699"/></a:solidFill></a:ln>
          </p:spPr></p:cxnSp>
          <p:cxnSp><p:nvCxnSpPr><p:cNvPr id="2" name="Vertical"/></p:nvCxnSpPr><p:spPr>
            <a:xfrm><a:off x="285750" y="95250"/><a:ext cx="0" cy="476250"/></a:xfrm>
            <a:prstGeom prst="line"><a:avLst/></a:prstGeom>
            <a:ln w="9525"><a:solidFill><a:srgbClr val="993366"/></a:solidFill></a:ln>
          </p:spPr></p:cxnSp>
        </p:spTree></p:sld>
        """, &theme)

    Swag.require(not page.simplified and page.shapes.count == 2)
    Swag.require(page.shapes[0].connector and page.shapes[0].positioned)
    Swag.require(page.shapes[0].bounds == Math.Rectangle{10, 20, 100, 0})
    Swag.require(page.shapes[1].connector and page.shapes[1].positioned)
    Swag.require(page.shapes[1].bounds == Math.Rectangle{30, 10, 0, 50})
    let html = page.canvasHtml(960, 720)
    Swag.require(Utf8.contains(html, "border-top:") and Utf8.contains(html, "border-left:"))
    Swag.require(Utf8.contains(html, "#336699") and Utf8.contains(html, "#993366"))
}

#test
{
    var theme = Pptx.SlideTheme.defaults()
    let page = expect Pptx.SlidePage.parse("""
        <p:sld><p:spTree><p:cxnSp><p:nvCxnSpPr><p:cNvPr id="1" name="Diagonal"/></p:nvCxnSpPr><p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="476250"/></a:xfrm>
          <a:prstGeom prst="line"><a:avLst/></a:prstGeom>
          <a:ln><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>
        </p:spPr></p:cxnSp></p:spTree></p:sld>
        """, &theme)

    Swag.require(not page.simplified and page.shapes[0].positioned)
    let html = page.canvasHtml(960, 720)
    Swag.require(Utf8.contains(html, "transform:rotate(26.5651deg)"))
    Swag.require(Utf8.contains(html, "border-top:") and Utf8.contains(html, "#000000"))
}

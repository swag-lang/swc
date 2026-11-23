#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// DrawingML tint and shade adjust HSL luminance while preserving hue and saturation.
#test
{
    let theme = Pptx.SlideTheme.defaults()
    Swag.require(theme.transformedColor("<a:srgbClr val='FF0000'><a:tint val='50000'/></a:srgbClr>") == "FF8080")
    Swag.require(theme.transformedColor("<a:srgbClr val='FF0000'><a:shade val='50000'/></a:srgbClr>") == "800000")
    Swag.require(theme.transformedColor("<a:srgbClr val='808080'><a:tint val='50000'/></a:srgbClr>") == "C0C0C0")
}

// Scheme aliases resolve through the slide color map before their ordered transforms.
#test
{
    var theme = Pptx.SlideTheme.defaults()
    theme.office.colors[4] = "0000FF"
    Swag.require(theme.transformedColor("<a:schemeClr val='accent1'><a:shade val='50000'/></a:schemeClr>") == "000080")
    Swag.require(theme.transformedColor("<a:schemeClr val='tx1'><a:tint val='50000'/></a:schemeClr>") == "808080")
    Swag.require(theme.transformedColor("<a:srgbClr val='FF0000'><a:tint val='50000'/><a:shade val='50000'/></a:srgbClr>") == "C00000")
}

// Invalid transform values do not leak malformed colors into generated HTML.
#test
{
    let theme = Pptx.SlideTheme.defaults()
    Swag.require(theme.transformedColor("<a:srgbClr val='GG0000'/>").isEmpty())
    Swag.require(theme.transformedColor("<a:srgbClr val='FF0000'><a:tint val='100001'/></a:srgbClr>").isEmpty())
}

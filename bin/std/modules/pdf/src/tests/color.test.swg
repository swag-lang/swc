#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

// Paints one filled rectangle per content fragment and returns the color each one carries.
private func filledColors(resources: string, content: string, extra: const [..] u8)->Array'Color
{
    var result: retval
    let document = expect Document.decode(singlePagePdf(resources, cast(const [..] u8) content, extra).toSlice())
    for item in document.pages[0].items where item.kind == .Path do
        result.add(item.itemFillColor())
    return result
}

// The device color operators set the fill and the stroke independently.
#test
{
    let content = "0.5 g 0 0 5 5 re f 1 0 0 rg 0 0 5 5 re f 0 1 1 0 k 0 0 5 5 re f"
    let colors  = filledColors("", content, "")
    @assert(colors.count == 3)
    @assert(colors[0].r == 128 and colors[0].g == 128 and colors[0].b == 128)
    @assert(colors[1].r == 255 and colors[1].g == 0 and colors[1].b == 0)
    @assert(colors[2].r == 255 and colors[2].g == 0 and colors[2].b == 0)
}

// `cs` and `scn` name a space from the page resources, then give it its components.
#test
{
    var extra: Array'u8
    addObject(&extra, 5, "<< /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [0 1 1 0] /N 1 >>")

    let resources = "/ColorSpace << /CsGray /DeviceGray /CsCmyk /DeviceCMYK /CsSpot [/Separation /Spot /DeviceCMYK 5 0 R] >>"
    let content = #raw """
/CsGray cs 0.25 scn 0 0 5 5 re f
/CsCmyk cs 0 0 0 1 scn 0 0 5 5 re f
/CsSpot cs 0.25 scn 0 0 5 5 re f
"""

    let colors = filledColors(resources, content, extra.toSlice())
    @assert(colors.count == 3)
    @assert(colors[0].r == 64 and colors[0].g == 64)
    @assert(colors[1].r == 0 and colors[1].g == 0 and colors[1].b == 0)

    // Without evaluating the tint transform, a spot color reads as the gray its tint darkens to.
    @assert(colors[2].r == 191 and colors[2].g == 191 and colors[2].b == 191)
}

// Selecting a space resets the current color to the black that space defines.
#test
{
    let content = "1 0 0 rg /DeviceCMYK cs 0 0 5 5 re f"
    let colors  = filledColors("", content, "")
    @assert(colors.count == 1)
    @assert(colors[0].r == 0 and colors[0].g == 0 and colors[0].b == 0)
}

// An indexed space addresses its palette through `scn` as well.
#test
{
    let resources = "/ColorSpace << /CsIndexed [/Indexed /DeviceRGB 2 <FF0000 00FF00 0000FF>] >>"
    let content   = "/CsIndexed cs 2 scn 0 0 5 5 re f 1 scn 0 0 5 5 re f"
    let colors    = filledColors(resources, content, "")
    @assert(colors.count == 2)
    @assert(colors[0].b == 255 and colors[0].r == 0)
    @assert(colors[1].g == 255 and colors[1].r == 0)
}

// An unknown space name leaves the page decodable rather than failing the document.
#test
{
    let colors = filledColors("", "/Missing cs 0 0 5 5 re f", "")
    @assert(colors.count == 1)
}

// `gs` carries the line width an ExtGState sets.
#test
{
    var extra: Array'u8
    addObject(&extra, 5, "<< /Type /ExtGState /LW 7 >>")

    let content  = "/GS0 gs 0 0 5 5 re S"
    let document = expect Document.decode(singlePagePdf("/ExtGState << /GS0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let item     = onlyItem(document.pages[0], .Path)
    @assert(item.pathStrokeWidth() == 7)
}

#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pixel, Pdf

// A 2 by 2 opaque red image.
private const RedSamples: [12] u8 = [255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]

// Builds a one-page document over a 200 by 100 page whose only XObject is the red image.
private func clipDocument(content: string)->Document
{
    var objects: Array'u8
    addStreamObject(&objects, 5, "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8", RedSamples)
    return expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, objects.toSlice()).toSlice())
}

// Renders the first page at one pixel per point over white.
private func renderClipped(document: *Document)->Image => expect document.editPage(0).render({scale: 1})

private func isRed(color: Color)->bool   => color.r > 200 and color.g < 60 and color.b < 60
private func isBlue(color: Color)->bool  => color.b > 200 and color.r < 60 and color.g < 60
private func isWhite(color: Color)->bool => color.r > 240 and color.g > 240 and color.b > 240

// A circle about `(cx, cy)` of radius `r`, as the four Béziers a content stream writes it with.
private func circlePath(cx, cy, r: f32)->String
{
    const K = 0.5523'f32
    let k = r * K
    var result: retval
    result += Format.toString("% % m ", cx + r, cy)
    result += Format.toString("% % % % % % c ", cx + r, cy + k, cx + k, cy + r, cx, cy + r)
    result += Format.toString("% % % % % % c ", cx - k, cy + r, cx - r, cy + k, cx - r, cy)
    result += Format.toString("% % % % % % c ", cx - r, cy - k, cx - k, cy - r, cx, cy - r)
    result += Format.toString("% % % % % % c ", cx + k, cy - r, cx + r, cy - k, cx + r, cy)
    result += "h"
    return result
}

// An image drawn through a round clip shows only what lies inside the circle.
#test
{
    var content: String = "q "
    content += circlePath(50, 50, 40).toString()
    content += " W n 80 0 0 80 10 10 cm /Im0 Do Q"

    var document = clipDocument(content.toString())
    let item     = onlyItem(document.pages[0], .Image)
    Swag.assert(item.clipPath != InvalidClipPath)

    // The centre is inside the circle; the corners of the image's square are outside it.
    let image = renderClipped(&document)
    Swag.assert(isRed(image.pixelColor(50, 50)))
    Swag.assert(isWhite(image.pixelColor(13, 87)))
    Swag.assert(isWhite(image.pixelColor(87, 13)))
    Swag.assert(isWhite(image.pixelColor(150, 50)))
}

// An axis-aligned rectangle stays a rectangle clip, exact and without a shape.
#test
{
    var document = clipDocument("q 20 20 50 50 re W n 0 0 1 rg 0 0 200 100 re f Q")
    let item     = onlyItem(document.pages[0], .Path)
    Swag.assert(item.clipPath == InvalidClipPath)
    Swag.assert(item.hasClip)
    Swag.assert(item.itemClip().rect == Math.Rectangle{20, 30, 50, 50})
}

// A filled path through a round clip is cut to the circle.
#test
{
    var content: String = "q "
    content += circlePath(50, 50, 40).toString()
    content += " W n 0 0 1 rg 0 0 200 100 re f Q"

    var document = clipDocument(content.toString())
    Swag.assert(onlyItem(document.pages[0], .Path).clipPath != InvalidClipPath)

    let image = renderClipped(&document)
    Swag.assert(isBlue(image.pixelColor(50, 50)))
    Swag.assert(isWhite(image.pixelColor(13, 87)))
    Swag.assert(isWhite(image.pixelColor(150, 50)))
}

// `W*` clips under the alternating rule: two nested squares leave a ring.
#test
{
    var document = clipDocument("q 10 10 80 80 re 30 30 40 40 re W* n 0 0 1 rg 0 0 200 100 re f Q")
    let image    = renderClipped(&document)
    Swag.assert(isBlue(image.pixelColor(20, 50)))
    Swag.assert(isWhite(image.pixelColor(50, 50)))
    Swag.assert(isWhite(image.pixelColor(150, 50)))
}

// A shape established inside another clips to their intersection.
#test
{
    var content: String = "q "
    content += circlePath(50, 50, 40).toString()
    content += " W n "
    content += circlePath(80, 50, 40).toString()
    content += " W n 0 0 1 rg 0 0 200 100 re f Q"

    var document = clipDocument(content.toString())
    let image    = renderClipped(&document)
    Swag.assert(isBlue(image.pixelColor(65, 50)))
    Swag.assert(isWhite(image.pixelColor(20, 50)))
    Swag.assert(isWhite(image.pixelColor(110, 50)))
}

// `Q` restores the clip that was in force before the shape was established.
#test
{
    var content: String = "q "
    content += circlePath(50, 50, 40).toString()
    content += " W n Q 0 0 1 rg 0 0 200 100 re f"

    var document = clipDocument(content.toString())
    Swag.assert(onlyItem(document.pages[0], .Path).clipPath == InvalidClipPath)
    Swag.assert(isBlue(renderClipped(&document).pixelColor(150, 50)))
}

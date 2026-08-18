#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pixel, Pdf

private func strokedPath(y: f32)->LinePathList
{
    var result: retval
    let line = result.newPath()
    line.start(20, y)
    line.lineTo(80, y)
    return result
}

// Stroke geometry survives decode, editing, encode, decode, and rasterization.
#test
{
    let content  = "2 J 1 j 7 M [10 5 3] 2 d 8 w 20 35 m 80 35 l S"
    var document = expect Document.decode(singlePagePdf("", cast(const [..] u8) content, "", "[0 0 100 50]").toSlice())
    let decoded  = onlyItem(document.pages[0], .Path)
    let style    = decoded.pathStrokeStyle()
    @assert(style.cap == .Square and style.join == .Round and style.miterLimit == 7)
    @assert(style.dashPattern.count == 6 and style.dashPattern[0] == 10 and style.dashPattern[3] == 10)
    @assert(style.dashPhase == 2)

    var editedStyle = PathStrokeStyle{cap: .Butt, join: .Bevel, miterLimit: 4}
    editedStyle.dashPattern.add(10)
    editedStyle.dashPattern.add(10)
    document.editPage(0).setPathStrokeStyle(0, editedStyle)
    let bytes   = expect document.encode()
    let encoded = cast(string) bytes.toSlice()
    @assert(Utf8.indexOf(encoded, "0 J\n2 j\n4 M\n[10 10] 0 d") != Swag.U64.Max)
    let roundTrip = expect Document.decode(bytes.toSlice())
    let final     = onlyItem(roundTrip.pages[0], .Path).pathStrokeStyle()
    @assert(final.cap == .Butt and final.join == .Bevel and final.miterLimit == 4)
    @assert(final.dashPattern.count == 2 and final.dashPattern[0] == 10 and final.dashPattern[1] == 10)

    let image = expect roundTrip.pages[0].render({background: Color.fromArgb(Argb.White)})
    @assert(image.pixelColor(25, 15).r < 32)
    @assert(image.pixelColor(35, 15).r > 223)
    @assert(image.pixelColor(45, 15).r < 32)
}

// The graphics-state stack restores the complete stroke style, including its owned dash array.
#test
{
    let content  = "2 J [8 4] -3 d q 1 J [2 2] 0 d 4 w 20 35 m 80 35 l S Q 4 w 20 15 m 80 15 l S"
    let document = expect Document.decode(singlePagePdf("", cast(const [..] u8) content, "", "[0 0 100 50]").toSlice())
    @assert(document.pages[0].items.count == 2)

    let nested   = document.pages[0].items[0].pathStrokeStyle()
    let restored = document.pages[0].items[1].pathStrokeStyle()
    @assert(nested.cap == .Round and nested.dashPattern[0] == 2 and nested.dashPhase == 0)
    @assert(restored.cap == .Square and restored.dashPattern[0] == 8 and restored.dashPhase == -3)
}

// The default PDF cap is flat; square caps extend by half the stroke width.
#test
{
    var document = Document.create()
    var page     = Page.create(100, 50)
    page.addPath(strokedPath(15), fill: false, stroke: true, strokeWidth: 10)
    page.addPath(strokedPath(35), fill: false, stroke: true, strokeWidth: 10, strokeStyle: {cap: .Square})
    document.addPage(#move page)

    let image = expect document.pages[0].render({background: Color.fromArgb(Argb.White)})
    @assert(image.pixelColor(16, 15).r > 223)
    @assert(image.pixelColor(16, 35).r < 32)
}

// A zero-width PDF stroke remains visible as a one-device-pixel hairline.
#test
{
    var document = Document.create()
    var page     = Page.create(100, 50)
    page.addPath(strokedPath(25), fill: false, stroke: true, strokeWidth: 0)
    document.addPage(#move page)

    let image       = expect document.pages[0].render({scale: 2, background: Color.fromArgb(Argb.White)})
    var hasHairline = false
    for y in 48 to 52
    {
        if image.pixelColor(100, y).r < 250
        {
            hasHairline = true
            break
        }
    }

    @assert(hasHairline)
}

// Malformed stroke parameters stop decoding instead of leaking impossible geometry to Pixel.
#test
{
    const Invalid: [4] string = ["0.5 J", "0 M", "[-1 2] 0 d", "-1 w"]
    for content in Invalid
    {
        let bytes = singlePagePdf("", cast(const [..] u8) content, "")
        discard catch Document.decode(bytes.toSlice()) as strokeError
        @assert(strokeError != null)
    }
}

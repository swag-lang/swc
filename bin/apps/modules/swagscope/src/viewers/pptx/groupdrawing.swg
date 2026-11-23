#global internal
#global namespace Viewers.Pptx

using Core

struct SlideGroup
{
    shapes:    Array'SlideShape
    supported: bool = true
}

impl SlideGroup
{
    // Reads one unrotated group whose children share a bounded uniform scale and translation.
    func parse(source: string, theme: const *SlideTheme, images: *Package.ImageCatalog? = null, pageWidth = 960.0)->SlideGroup fail
    {
        var result: #returntype
        var scan = Package.Scanner.create(source)
        var token: Package.Token
        var groupDepth = 0'u32
        var inGroupProperties = false
        var inGroupTransform = false
        var hasOffset = false
        var hasExtent = false
        var hasChildOffset = false
        var hasChildExtent = false
        var groupBounds: Math.Rectangle
        var childOffset: Math.Vector2
        var childExtent: Math.Vector2
        var rotated = false
        var flipped = false
        var shapeStart = Swag.U64.Max
        var shapeName: String
        var scaleX = 1.0'f32
        var scaleY = 1.0'f32

        while true
        {
            let at = scan.offset
            if not scan.next(&token) do
                break
            if token.kind == .Start
            {
                if token.isElement("grpSp")
                {
                    groupDepth += 1
                    if groupDepth > 1 do
                        result.supported = false
                }

                if groupDepth == 1 and token.isElement("grpSpPr") do
                    inGroupProperties = true
                if inGroupProperties and token.isElement("xfrm")
                {
                    inGroupTransform = not token.empty
                    let rotation = catch StrConv.toS64(token.attribute("rot") orelse "0") orelse Swag.S64.Max
                    rotated = rotation != 0
                    flipped = token.attribute("flipH") == "1" or token.attribute("flipH") == "true" or
                              token.attribute("flipV") == "1" or token.attribute("flipV") == "true"
                }
                elif inGroupTransform and token.isElement("off")
                {
                    groupBounds.x = SlideGroup.readGroupCoordinate(&token, "x")
                    groupBounds.y = SlideGroup.readGroupCoordinate(&token, "y")
                    hasOffset = true
                }
                elif inGroupTransform and token.isElement("ext")
                {
                    groupBounds.width = SlideGroup.readGroupCoordinate(&token, "cx")
                    groupBounds.height = SlideGroup.readGroupCoordinate(&token, "cy")
                    hasExtent = true
                }
                elif inGroupTransform and token.isElement("chOff")
                {
                    childOffset.x = SlideGroup.readGroupCoordinate(&token, "x")
                    childOffset.y = SlideGroup.readGroupCoordinate(&token, "y")
                    hasChildOffset = true
                }
                elif inGroupTransform and token.isElement("chExt")
                {
                    childExtent.x = SlideGroup.readGroupCoordinate(&token, "cx")
                    childExtent.y = SlideGroup.readGroupCoordinate(&token, "cy")
                    hasChildExtent = true
                    scaleX = groupBounds.width / Math.max(childExtent.x, 1)
                    scaleY = groupBounds.height / Math.max(childExtent.y, 1)
                }

                if groupDepth > 0 and shapeStart == Swag.U64.Max and
                   (token.isElement("sp") or token.isElement("pic") or token.isElement("cxnSp") or token.isElement("graphicFrame"))
                {
                    shapeStart = at
                    shapeName = token.name
                    if token.isElement("graphicFrame") do
                        result.supported = false
                }
            }

            if token.kind == .End
            {
                if token.isElement("xfrm") do
                    inGroupTransform = false
                if token.isElement("grpSpPr") do
                    inGroupProperties = false
                if token.isElement("grpSp") do
                    groupDepth -= 1
            }

            if shapeStart != Swag.U64.Max and token.name == shapeName and
               (token.kind == .End or token.empty)
            {
                let childPageWidth = Math.abs(scaleX - scaleY) < 0.0001 and scaleX >= 0.01 and scaleX <= 100 ? pageWidth / scaleX : pageWidth
                var shape = try SlideShape.parse(source[shapeStart until scan.offset], theme, images, childPageWidth)
                result.supported = result.supported and not shape.unsupported
                if not shape.hidden do
                    result.shapes.add(shape)
                shapeStart = Swag.U64.Max
                shapeName.clear()
            }

            if token.empty and token.isElement("grpSp") do
                groupDepth -= 1
        }

        if scan.damaged or shapeStart != Swag.U64.Max do
            fail Errors.InvalidFormatError{texts().err_Invalid}

        result.supported = result.supported and hasOffset and hasExtent and hasChildOffset and hasChildExtent and
                           not rotated and not flipped and groupBounds.width > 0 and groupBounds.height > 0 and
                           childExtent.x > 0 and childExtent.y > 0 and scaleX >= 0.01 and scaleX <= 100 and
                           Math.abs(scaleX - scaleY) < 0.0001 and not result.shapes.isEmpty()
        if not result.supported do
            return result

        for &shape in result.shapes
        {
            if not shape.positioned
            {
                result.supported = false
                break
            }

            shape.bounds.x = groupBounds.x + (shape.bounds.x - childOffset.x) * scaleX
            shape.bounds.y = groupBounds.y + (shape.bounds.y - childOffset.y) * scaleX
            shape.bounds.width *= scaleX
            shape.bounds.height *= scaleX
            shape.fontSize = cast(u32, Math.round(cast(f32, shape.fontSize) * scaleX))
            shape.lineWidth *= scaleX
            shape.inset *= scaleX
        }

        return result
    }

    private func readGroupCoordinate(token: const *Package.Token, name: string)->f32
    {
        let value = catch StrConv.toS64(token.attribute(name) orelse "") orelse 0
        return cast(f32, Math.clamp(value, -100_000_000's64, 100_000_000's64)) / 9525
    }
}

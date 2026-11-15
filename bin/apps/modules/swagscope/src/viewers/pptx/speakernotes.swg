#global internal
#global namespace Viewers.Pptx

using Core

// Speaker prose belongs to its slide. Notes-page thumbnails, footers and counters do not.
func readSpeakerNotes(source: string, theme: const *SlideTheme)->String fail
{
    var result: String
    var scan   = Package.Scanner.create(source)
    var token:  Package.Token
    var start  = Swag.U64.Max
    var shapes = 0'u32
    while true
    {
        let at = scan.offset
        if not scan.next(&token) do
            break
        if token.kind == .Start and token.isElement("sp")
        {
            if start != Swag.U64.Max do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            start = at
        }

        if start != Swag.U64.Max and token.isElement("sp") and (token.kind == .End or token.empty)
        {
            let shapeSource = source[start until scan.offset]
            let shape       = try SlideShape.parse(shapeSource, theme)
            if not shape.hidden and (not shape.placeholder or shape.placeholderKind == "body")
            {
                var images: Package.ImageCatalog
                let text  = try SlideText.parse(shapeSource, &images, theme, 960, readerStyle: true)
                var plain = text.plainText
                plain.trim()
                if not plain.isEmpty() do
                    result += text.html
            }

            start  = Swag.U64.Max
            shapes += 1
            if shapes > 2048 or result.count > 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }

    if scan.damaged or start != Swag.U64.Max do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

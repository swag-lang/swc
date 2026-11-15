#global internal
#global namespace Viewers.Odp

using Core

// A notes frame contains the prose; notes-page images and page-number fields stay out.
func readSpeakerNotes(source: string, styles: const *Odf.StyleCatalog)->String fail
{
    var result: String
    var scan    = Package.Scanner.create(source)
    var token:  Package.Token
    var start   = Swag.U64.Max
    var include = false
    var frames  = 0'u32
    while true
    {
        let at = scan.offset
        if not scan.next(&token) do
            break
        if token.kind == .Start and token.isElement("frame")
        {
            if start != Swag.U64.Max do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            start = at
            let kind = token.attribute("class")
            include = (kind == null or kind == "notes") and
                      token.attribute("display") != "none" and
                      token.attribute("visibility") != "hidden"
        }

        if start != Swag.U64.Max and token.isElement("frame") and (token.kind == .End or token.empty)
        {
            if include
            {
                let text  = try readText(source[start until scan.offset], styles, {}, 960, readerStyle: true)
                var plain = text.plain
                plain.trim()
                if not plain.isEmpty() do
                    result += text.html
            }

            start  = Swag.U64.Max
            frames += 1
            if frames > 2048 or result.count > 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }

    if scan.damaged or start != Swag.U64.Max do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

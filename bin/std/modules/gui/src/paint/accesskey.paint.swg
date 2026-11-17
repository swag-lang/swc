#global internal

using Core, Pixel

// Draws plain caption text with its matching rune underlined only while Alt access keys are shown.
func drawAccessKeyText(painter: *Painter, position: Math.Rectangle, text: *RichString, format: RichStringFormat, accessKey: rune, visible: bool)
{
    if not visible or accessKey == 0
    {
        painter.drawRichString(position, text, format)
        return
    }

    text.compute()
    for chunk in text.chunks
    {
        if chunk.hasFontStyle or chunk.under != .None or chunk.colorIdx != 0 or chunk.isUrl
        {
            painter.drawRichString(position, text, format)
            return
        }
    }

    let bytes    = cast(const [..] u8, text.text)
    var offset:  u64
    var keyStart = Swag.U64.Max
    var keySize: u64
    while offset < bytes.count
    {
        let {c, eat} = Utf8.decodeRune(Swag.makeSlice(bytes.buffer + offset, bytes.count - offset))
        if Unicode.toLower(c) == Unicode.toLower(accessKey)
        {
            keyStart = offset
            keySize  = eat
            break
        }

        offset += eat
    }

    if keyStart == Swag.U64.Max
    {
        painter.drawRichString(position, text, format)
        return
    }

    var marked: RichString
    if keyStart > 0 do
        marked.append(text.text[0 until keyStart])
    marked.append(text.text[keyStart until keyStart + keySize], {underline: .Underline})
    if keyStart + keySize < bytes.count do
        marked.append(text.text[keyStart + keySize to])
    painter.drawRichString(position, &marked, format)
}

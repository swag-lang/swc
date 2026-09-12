#global namespace Clipboard

using Serialization

var g_ValueFormat: ValueFormat

// Copies a supported value or serializable typed value to the clipboard.
public func addTypedValue(value: *void, type: typeinfo)
{
    switch type
    {
    case string:
        return addString(value[as string])

    case Core.String:
        let str = cast(*Core.String) value
        return addString(str.toString())

    case Pixel.Image:
        return addImage(value[as Pixel.Image])
    }

    var buf:    ConcatBuffer
    var encode: Encoder'Write.TagBin
    catch
    {
        try encode.start(&buf, type)
        try encode.writeValue(value, type)
        try encode.end()
    }
    else {}

    buf.makeLinear()
    addTypedData(g_ValueFormat, type, buf.toSlice()!)
}

// Reports whether the clipboard contains a value compatible with `type`.
public func hasTypedValue(type: typeinfo)->bool
{
    switch type
    {
    case string, Core.String: return hasString()
    case Pixel.Image:         return hasImage()
    }

    return hasTypedData(g_ValueFormat, type)
}

// Decodes a clipboard value into initialized storage and reports success.
public func getTypedValue(value: *void, type: typeinfo)->bool
{
    if not hasTypedValue(type) do
        return false

    switch type
    {
    case Core.String:
        value[as Core.String] = getString()
        return true

    case Pixel.Image:
        value[as Pixel.Image] = getImage()
        return true
    }

    let data = getTypedData(g_ValueFormat, type)

    var decoder: Decoder'Read.TagBin
    catch
    {
        try decoder.start(data.toSlice(), type)
        try decoder.readTypedContent(value, type)
        try decoder.end()
    }
    else
    {
        return false
    }

    return true
}

#init
{
    g_ValueFormat = catch registerFormat("Swag.Clipboard.TypeValue")
}

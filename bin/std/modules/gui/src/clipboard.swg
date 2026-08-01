#global namespace Clipboard

using Serialization

var g_ValueFormat: ValueFormat

// Copies a supported value or serializable typed value to the clipboard.
public func addTypedValue(value: *void, type: typeinfo)
{
    switch type
    {
    case string:
        return addString(dref cast(*string) value)

    case Core.String:
        let str = cast(*Core.String) value
        return addString(str.toString())

    case Pixel.Image:
        return addImage(dref cast(*Pixel.Image) value)
    }

    var buf:    ConcatBuffer
    var encode: Encoder'Write.TagBin
    catch
    {
        encode.start(&buf)
        encode.writeValue(value, type)
        encode.end()
    } else {}

    buf.makeLinear()
    addTypedData(g_ValueFormat, type, notnull buf.toSlice())
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
    if !hasTypedValue(type) do
        return false

    switch type
    {
    case Core.String:
        dref cast(*Core.String) value = getString()
        return true

    case Pixel.Image:
        dref cast(*Pixel.Image) value = getImage()
        return true
    }

    let data = getTypedData(g_ValueFormat, type)

    var decoder: Decoder'Read.TagBin
    catch
    {
        decoder.start(data.toSlice())
        decoder.readTypedContent(value, type)
        decoder.end()
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

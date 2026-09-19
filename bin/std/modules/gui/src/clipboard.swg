#global namespace Clipboard

using Serialization

var g_ValueFormat: ValueFormat

// Publishes the value `value` points to, of type `type`, on the clipboard.
//
// A `string` or a [[Core.String]] is published as text through [[Gui.Clipboard.addString]], and a
// [[Pixel.Image]] replaces the clipboard content through [[Gui.Clipboard.addImage]]. Any other type
// is serialized with [[Core.Serialization.Write.TagBin]] and published through
// [[Gui.Clipboard.addTypedData]] with the fingerprint of `type`, so only a reader asking for that
// same type finds it.
public func addTypedValue(value: *void, type: typeinfo)
{
    switch type
    {
    case string:      return addString((cast(const *string) value)[])
    case Core.String: return addString((cast(const *Core.String) value).toString())
    case Pixel.Image: return addImage((cast(const *Pixel.Image) value)[])
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

// Reports whether the clipboard holds a value compatible with `type`.
//
// Text is compatible with `string` and [[Core.String]], and an image with [[Pixel.Image]]. Any
// other type needs a payload that [[Gui.Clipboard.addTypedValue]] published for that same type.
public func hasTypedValue(type: typeinfo)->bool
{
    switch type
    {
    case string, Core.String: return hasString()
    case Pixel.Image:         return hasImage()
    }

    return hasTypedData(g_ValueFormat, type)
}

// Reads the clipboard value into the storage `value` points to, of type `type`, and reports whether it succeeded.
//
// The storage must be initialized, because the value it holds is replaced. A [[Core.String]]
// receives the clipboard text and a [[Pixel.Image]] the clipboard image. Any other type is decoded
// from a payload that [[Gui.Clipboard.addTypedValue]] published for that same type. A `string`
// is not supported and answers `false`.
public func getTypedValue(value: *void, type: typeinfo)->bool
{
    if not hasTypedValue(type) do
        return false

    switch type
    {
    case Core.String:
        (cast(*Core.String) value)[] = getString()
        return true

    case Pixel.Image:
        (cast(*Pixel.Image) value)[] = getImage()
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

#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A data URI round-trips through the codec registry: the media type selects the decoder the
// way a file extension does, and a parameter riding along with it does not hide the subtype.
#test
{
    var source = Image.create(4, 3, .RGBA8)
    source.fill(Color.fromArgb(255'u8, 40'u8, 80'u8, 120'u8))
    let bytes = expect source.encodeToBytes("embedded.png")

    var plain: String = "data:image/png;base64,"
    plain += Base64.encode(bytes.toSlice())
    let decoded = expect Image.fromDataUri(plain.toString())
    Swag.assert(decoded.width == 4 and decoded.height == 3)
    Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)

    var withParameter: String = "data:image/png;name=figure;base64,"
    withParameter += Base64.encode(bytes.toSlice())
    let parameterized = expect Image.fromDataUri(withParameter.toString())
    Swag.assert(parameterized.width == 4 and parameterized.height == 3)
}

// `image/jpeg` names the decoder registered under `jpg`, which is how every generator spells
// that media type.
#test
{
    var source = Image.create(8, 8, .RGB8)
    source.fill(Color.fromArgb(255'u8, 128'u8, 128'u8, 128'u8))
    let bytes = expect source.encodeToBytes("embedded.jpg")

    var uri: String = "data:image/jpeg;base64,"
    uri += Base64.encode(bytes.toSlice())
    let decoded = expect Image.fromDataUri(uri.toString())
    Swag.assert(decoded.width == 8 and decoded.height == 8)
}

// A reference that is not an inline image reports a failure the caller can degrade on, never a
// decode of garbage: wrong scheme, missing base64 marker, unknown media type, broken payload.
#test
{
    discard catch Image.fromDataUri("data:text/plain;base64,aGk=") as notImage
    Swag.assert(notImage != null)

    discard catch Image.fromDataUri("data:image/png,plain") as notBase64
    Swag.assert(notBase64 != null)

    discard catch Image.fromDataUri("data:image/unknown;base64,aGk=") as noCodec
    Swag.assert(noCodec != null)

    discard catch Image.fromDataUri("data:image/png;base64,!!!") as badPayload
    Swag.assert(badPayload != null)
}

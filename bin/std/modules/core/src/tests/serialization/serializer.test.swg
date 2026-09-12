#global if #command == Swag.CompilerCommand.Test
#global private

struct SerializerPayload
{
    number: u32
    active: bool
}

// Instantiate both the scalar interface calls and the reflected-value fallback.
func(T) roundTripSerializedField(value: T)->T fail
{
    var buffer:     ConcatBuffer
    var encoder:    Serialization.Encoder'Serialization.Write.TagBin
    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var serializer: Serialization.Serializer
    var stored = value

    try serializer.startWrite(&encoder, &buffer)
    try serializer.beginSection()
    try serializer.serialize("value", &stored)
    try serializer.endSection()
    try serializer.end()

    var result: retval
    try serializer.startRead(&decoder, buffer.toSlice()!)
    try serializer.beginSection()
    try serializer.serialize("value", &result)
    try serializer.endSection()
    try serializer.end()
    return result
}

#test
{
    let number = expect roundTripSerializedField(42'u32)
    Swag.assert(number == 42)

    let payload = expect roundTripSerializedField(SerializerPayload{number: 7, active: true})
    Swag.assert(payload.number == 7)
    Swag.assert(payload.active)
}

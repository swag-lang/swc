#global if #command == Swag.CompilerCommand.Test
#global private

struct SerializerPayload
{
    number: u32
    active: bool
}

// Instantiate both the scalar interface calls and the reflected-value fallback.
#[Swag.Propagate]
func(T) roundTripSerializedField(value: T)->T fail
{
    var buffer:     ConcatBuffer
    var encoder:    Serialization.Encoder'Serialization.Write.TagBin
    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var serializer: Serialization.Serializer
    var stored = value

    serializer.startWrite(&encoder, &buffer)
    serializer.beginSection()
    serializer.serialize("value", &stored)
    serializer.endSection()
    serializer.end()

    var result: retval
    serializer.startRead(&decoder, buffer.toSlice()!)
    serializer.beginSection()
    serializer.serialize("value", &result)
    serializer.endSection()
    serializer.end()
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

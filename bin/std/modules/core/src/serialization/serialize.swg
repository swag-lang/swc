#global export
#global namespace Serialization

using Swag

// Set the struct version number
#[AttrUsage(AttributeUsage.Struct)]
attr Version(v: u32)

// The struct does not need versionning
#[AttrUsage(AttributeUsage.Struct)]
attr Final()

// Accept this other name for the struct field or the struct itself
#[AttrUsage(AttributeUsage.Struct | AttributeUsage.StructVariable | AttributeUsage.Multi)]
attr Alias(name: string)

// Do not serialize a struct or a field
#[AttrUsage(AttributeUsage.Struct | AttributeUsage.StructVariable)]
attr NoSerialize()

// Compress a struct or a field
#[AttrUsage(AttributeUsage.Struct | AttributeUsage.StructVariable)]
attr Compress()

// Defines the operations supported by i serialize.
interface ISerialize
{
    // Performs the read operation.
    mtd read(decoder: IDecoder)->bool fail
    // Performs the write operation.
    mtd write(encoder: IEncoder)->bool fail
    // Reads element.
    mtd readElement(type: TypeValue, data: #null *void, decoder: IDecoder)->bool fail
    // Writes element.
    mtd writeElement(type: TypeValue, data: #null const *void, encoder: IEncoder)->bool fail
    // Posts read.
    mtd postRead(data: #null *void, decoder: IDecoder) fail
}

// Represents serializer.
struct Serializer
{
    encode:  #null IEncoder // Encode associated with this value.
    decode:  #null IDecoder // Decode associated with this value.
    isWrite: bool // Whether this value is write.
}

impl Serializer
{
    // Returns whether writing.
    #[Swag.Inline]
    mtd isWriting() => .isWrite
    // Returns whether reading.
    #[Swag.Inline]
    mtd isReading() => !.isWrite

    // Start encoding
    mtd startWrite(encoder: IEncoder, output: *ConcatBuffer) fail
    {
        .encode  = encoder
        .isWrite = true
        .encode.start(output)
    }

    // Start decoding
    mtd startRead(decoder: IDecoder, input: const [..] u8) fail
    {
        .decode  = decoder
        .isWrite = false
        .decode.start(input)
    }

    // End encoding/decoding
    mtd end() fail
    {
        if .isWrite
        {
            let encode = notnull .encode
            encode.end()
        }
        else
        {
            let decode = notnull .decode
            decode.end()
        }
    }

    // Start a new section
    mtd beginSection(kind = SectionKind.Unordered) fail
    {
        if .isWrite
        {
            let encode = notnull .encode
            encode.beginSection(kind)
        }
        else
        {
            let decode = notnull .decode
            decode.beginSection(kind)
        }
    }

    // End the previous section
    mtd endSection() fail
    {
        if .isWrite
        {
            let encode = notnull .encode
            encode.endSection()
        }
        else
        {
            let decode = notnull .decode
            decode.endSection()
        }
    }

    // Serialize one value
    #[Swag.Optimize(false)]
    mtd(MT) serialize(name: string, crc: u32, res: *MT) fail
    {
        var value: Swag.TypeValue
        value.name        = name
        value.crc         = crc
        value.pointedType = #typeof(MT)

        if .isWrite
        {
            let encode = notnull .encode
            encode.beginField(value)
            defer #nofail encode.endField(value)

            #static switch MT
            {
            case s8:        encode.writeS8(dref res)
            case s16:       encode.writeS16(dref res)
            case s32:       encode.writeS32(dref res)
            case s64:       encode.writeS64(dref res)
            case u8:        encode.writeU8(dref res)
            case u16:       encode.writeU16(dref res)
            case u32, rune: encode.writeU32(dref res)
            case u64:       encode.writeU64(dref res)
            case bool:      encode.writeBool(dref res)
            case f32:       encode.writeF32(dref res)
            case f64:       encode.writeF64(dref res)
            default:        encode.write(res, #typeof(MT))
            }
        }
        else
        {
            let decode = notnull .decode
            if !decode.beginField(value) do
                return
            defer #nofail decode.endField(value)

            #static switch MT
            {
            case s8:        dref res = decode.readS8()
            case s16:       dref res = decode.readS16()
            case s32:       dref res = decode.readS32()
            case s64:       dref res = decode.readS64()
            case u8:        dref res = decode.readU8()
            case u16:       dref res = decode.readU16()
            case u32, rune: dref res = decode.readU32()
            case u64:       dref res = decode.readU64()
            case bool:      dref res = decode.readBool()
            case f32:       dref res = decode.readF32()
            case f64:       dref res = decode.readF64()
            default:        decode.read(res, #typeof(MT))
            }
        }
    }

    // Serialize one value
    #[Swag.Mixin]
    mtd(MT) serialize(name: string, res: *MT) fail
    {
        .serialize(name, Hash.Crc32.compute(name), res)
    }
}

#global export
#global namespace Serialization

using Swag

// Defines the version number written with a serialized struct.
#[AttrUsage(AttributeUsage.Struct)]
attr Version(v: u32)

// Serializes a POD struct as raw bytes without structural versioning.
#[AttrUsage(AttributeUsage.Struct)]
attr Final()

// Defines the stable, human-readable identity of a serialized document.
//
// TagBin writes this value in its header and checks it before decoding the root value.
// Keep it unchanged when the Swag type or its owning module is renamed.
#[AttrUsage(AttributeUsage.Struct)]
attr Schema(name: string)

// Defines the stable, human-readable wire name of a field.
//
// A field without this attribute uses its source name.
#[AttrUsage(AttributeUsage.StructVariable)]
attr Key(name: string)

// Defines the stable, human-readable wire identity of a serialized struct type.
//
// A concrete struct stored through an interface always needs this attribute so its
// identity does not depend on a Swag type or module name.
#[AttrUsage(AttributeUsage.Struct)]
attr TypeKey(name: string)

// Excludes a struct or field from serialization.
#[AttrUsage(AttributeUsage.Struct | AttributeUsage.StructVariable)]
attr NoSerialize()

// Compresses the serialized payload of a struct or field.
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
    // Which direction the serializer runs in. Established by 'startWrite' or 'startRead'.
    public readonly isWrite: bool

    // The backend the serializer drives. It is chosen by 'startWrite' and 'startRead', which
    // also pair it with the matching 'end'.
    internal
    {
        encode: #null IEncoder     // Encoder used while writing.
        decode: #null IDecoder     // Decoder used while reading.
    }
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
            let encode = .encode!
            encode.end()
        }
        else
        {
            let decode = .decode!
            decode.end()
        }
    }

    // Start a new section
    mtd beginSection(kind = SectionKind.Unordered) fail
    {
        if .isWrite
        {
            let encode = .encode!
            encode.beginSection(kind)
        }
        else
        {
            let decode = .decode!
            decode.beginSection(kind)
        }
    }

    // End the previous section
    mtd endSection() fail
    {
        if .isWrite
        {
            let encode = .encode!
            encode.endSection()
        }
        else
        {
            let decode = .decode!
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
            let encode = .encode!
            encode.beginField(value)
            defer #nofail encode.endField(value)

            #static switch MT
            {
            case s8:        encode.writeS8(res[])
            case s16:       encode.writeS16(res[])
            case s32:       encode.writeS32(res[])
            case s64:       encode.writeS64(res[])
            case u8:        encode.writeU8(res[])
            case u16:       encode.writeU16(res[])
            case u32, rune: encode.writeU32(res[])
            case u64:       encode.writeU64(res[])
            case bool:      encode.writeBool(res[])
            case f32:       encode.writeF32(res[])
            case f64:       encode.writeF64(res[])
            default:        encode.write(res, #typeof(MT))
            }
        }
        else
        {
            let decode = .decode!
            if !decode.beginField(value) do
                return
            defer #nofail decode.endField(value)

            #static switch MT
            {
            case s8:        res[] = decode.readS8()
            case s16:       res[] = decode.readS16()
            case s32:       res[] = decode.readS32()
            case s64:       res[] = decode.readS64()
            case u8:        res[] = decode.readU8()
            case u16:       res[] = decode.readU16()
            case u32, rune: res[] = decode.readU32()
            case u64:       res[] = decode.readU64()
            case bool:      res[] = decode.readBool()
            case f32:       res[] = decode.readF32()
            case f64:       res[] = decode.readF64()
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

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

// Lets a struct take over part or all of its own serialization.
//
// A struct that implements it is asked first: returning false from a method hands the work
// back to the reflected field-by-field path.
interface ISerialize
{
    // Reads the whole value from `decoder` and returns true, or returns false to have the decoder read it field by field.
    mtd read(decoder: IDecoder)->bool fail

    // Writes the whole value to `encoder` and returns true, or returns false to have the encoder write it field by field.
    mtd write(encoder: IEncoder)->bool fail

    // Reads the field `type` into `data` and returns true, or returns false to have the decoder read it.
    mtd readElement(type: TypeValue, data: *void?, decoder: IDecoder)->bool fail

    // Writes the field `type` from `data` and returns true, or returns false to have the encoder write it.
    mtd writeElement(type: TypeValue, data: const *void?, encoder: IEncoder)->bool fail

    // Runs after the decoder has read every field of the value at `data`, so derived state can be rebuilt.
    mtd postRead(data: *void?, decoder: IDecoder) fail
}

// Drives a read or a write through one code path, so a single function can both save and load a value.
//
// ```swag
// func serializeSettings(serializer: *Serialization.Serializer, settings: *Settings) fail
// {
//     try serializer.beginSection()
//     try serializer.serialize("width", &settings.width)
//     try serializer.serialize("height", &settings.height)
//     try serializer.endSection()
// }
// ```
struct Serializer
{
    // Which direction the serializer runs in. Established by 'startWrite' or 'startRead'.
    public readonly isWrite: bool

    // The backend the serializer drives. It is chosen by 'startWrite' and 'startRead', which
    // also pair it with the matching 'end'.

    internal
    {
        encode: IEncoder?     // Encoder used while writing.
        decode: IDecoder?     // Decoder used while reading.
    }
}

impl Serializer
{
    // Returns whether the serializer writes.
    #[Swag.Inline]
    mtd isWriting()->bool => .isWrite

    // Returns whether the serializer reads.
    #[Swag.Inline]
    mtd isReading()->bool => not .isWrite

    // Starts writing to `output` through `encoder`.
    mtd startWrite(encoder: IEncoder, output: *ConcatBuffer) fail
    {
        .encode  = encoder
        .isWrite = true
        try .encode.start(output)
    }

    // Starts reading the borrowed `input` through `decoder`.
    mtd startRead(decoder: IDecoder, input: const [..] u8) fail
    {
        .decode  = decoder
        .isWrite = false
        try .decode.start(input)
    }

    // Finishes the write or the read.
    mtd end() fail
    {
        if .isWrite do
            try .encode!.end()
        else do
            try .decode!.end()
    }

    // Opens a section of kind `kind`.
    mtd beginSection(kind = SectionKind.Unordered) fail
    {
        if .isWrite do
            try .encode!.beginSection(kind)
        else do
            try .decode!.beginSection(kind)
    }

    // Closes the current section.
    mtd endSection() fail
    {
        if .isWrite do
            try .encode!.endSection()
        else do
            try .decode!.endSection()
    }

    // Writes `res` as the field `name`, or reads that field into `res`.
    //
    // `crc` identifies the field on the wire. When reading, a field the input does not contain
    // leaves `res` unchanged.
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
            try encode.beginField(value)
            defer #nofail try encode.endField(value)

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
            default:        try encode.write(res, #typeof(MT))
            }
        }
        else
        {
            let decode = .decode!
            if not (try decode.beginField(value)) do
                return
            defer #nofail try decode.endField(value)

            #static switch MT
            {
            case s8:        res[] = try decode.readS8()
            case s16:       res[] = try decode.readS16()
            case s32:       res[] = try decode.readS32()
            case s64:       res[] = try decode.readS64()
            case u8:        res[] = try decode.readU8()
            case u16:       res[] = try decode.readU16()
            case u32, rune: res[] = try decode.readU32()
            case u64:       res[] = try decode.readU64()
            case bool:      res[] = try decode.readBool()
            case f32:       res[] = try decode.readF32()
            case f64:       res[] = try decode.readF64()
            default:        try decode.read(res, #typeof(MT))
            }
        }
    }

    // Serializes `res` as the field `name`, identified by the CRC-32 of `name`.
    #[Swag.Mixin]
    mtd(MT) serialize(name: string, res: *MT) fail
    {
        try .serialize(name, Hash.Crc32.compute(name), res)
    }
}

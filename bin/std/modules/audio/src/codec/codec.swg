using Core

var g_Codecs: Array'CodecDesc

// Converts encoded audio incrementally between sound-file encodings.
//
// A codec instance is created per streaming voice. Implementations borrow the
// input and output buffers only for the duration of each call and must never
// read or write beyond the supplied byte lengths.
public interface ICodec
{
    // Returns whether this codec can produce `encoding`.
    mtd canEncode(encoding: SoundFileEncoding)->bool

    // Returns whether this codec can consume `encoding`.
    mtd canDecode(encoding: SoundFileEncoding)->bool

    // Initializes decoder state and returns the number of input bytes consumed.
    //
    // `srcBuffer` contains up to `srcLength` bytes from the start of the encoded
    // stream. Implementations may consume headers or initial sample data.
    mtd initialize(source: [*] void, sourceSize: u64)->u64 fail

    // Decodes one chunk and reports produced and consumed byte counts.
    //
    // At most `destinationSize` bytes may be written to `destination`, and at most
    // `sourceSize` bytes may be read from `source`.
    mtd decode(destination: [*] void, destinationSize: u64, source: [*] void, sourceSize: u64)->CodecProgress fail
}

// Reports the byte-level progress of one incremental codec operation.
public struct CodecProgress
{
    bytesWritten: u64     // Bytes produced in the destination buffer.
    bytesRead:    u64     // Bytes consumed from the source buffer.
}

struct CodecDesc
{
    type: const *Swag.TypeInfoStruct
    itf:  ICodec
}

// Registers a codec implementation for subsequent voice creation.
//
// `T` must implement [[Audio.ICodec]]. Registration stores its type and
// interface dispatch table; codec instances are allocated on demand.
public func(T) registerCodec()
{
    #assert(Reflection.hasInterface(#typeof(T), ICodec))

    registerCodecImplementation(#typeof(T), @mkinterface(null, #typeof(T), ICodec))
}

// Non-generic bridge used by registerCodec after its body is instantiated in the caller's
// module. The registry itself remains module-internal.
#[Swag.NoDoc]
public func registerCodecImplementation(type: const *Swag.TypeInfoStruct, itf: ICodec)
{
    var desc: CodecDesc = undefined
    desc.type = type
    desc.itf  = itf
    g_Codecs.add(desc)
}

// Find the codec that can treat the given encoding
func findCodec(destinationEncoding, sourceEncoding: SoundFileEncoding)->#null *CodecDesc
{
    var found: #null *CodecDesc
    for &codec in g_Codecs
    {
        if codec.itf.canEncode(destinationEncoding) and codec.itf.canDecode(sourceEncoding)
        {
            found = codec
            break
        }
    }

    return found
}

// Stores the source, destination, and concrete type of a codec instance.
public struct Codec
{
    sourceEncoding:      SoundFileEncoding     // Encoding read from the sound file.
    destinationEncoding: SoundFileEncoding     // Encoding requested by the active backend.
    // Concrete codec type used for destruction.
    #[Swag.Late]
    type: const *Swag.TypeInfoStruct
}

// Initialize predefined codecs
#init
{
    registerCodec'CodecPcmToPcm16()
}

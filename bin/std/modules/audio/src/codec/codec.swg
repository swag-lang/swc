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
    mtd init(srcBuffer: [*] void, srcLength: u64)->u64 fail

    // Decodes one chunk and reports produced and consumed byte counts.
    //
    // At most `destLength` bytes may be written to `destBuffer`, and at most
    // `srcLength` bytes may be read from `srcBuffer`. `write` is the number of
    // destination bytes produced; `read` is the number of source bytes consumed.
    mtd decode(destBuffer: [*] void, destLength: u64, srcBuffer: [*] void, srcLength: u64)->{ write, read: u64 } fail
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
public func(T) addCodec()
{
    #assert(Reflection.hasInterface(#typeof(T), ICodec))

    var desc: CodecDesc = undefined
    desc.type = #typeof(T)
    desc.itf  = @mkinterface(null, #typeof(T), ICodec)
    g_Codecs.add(desc)
}

// Find the codec that can treat the given encoding
func getCodec(dstEncoding, srcEncoding: SoundFileEncoding)->#null *CodecDesc
{
    var found: #null *CodecDesc
    for &codec in g_Codecs
    {
        if codec.itf.canEncode(dstEncoding) and codec.itf.canDecode(srcEncoding)
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
    srcEncoding: SoundFileEncoding // Encoding read from the sound file.
    dstEncoding: SoundFileEncoding // Encoding requested by the active backend.
    // Concrete codec type used for destruction.
    #[Swag.Late]
    type: const *Swag.TypeInfoStruct
}

// Initialize predefined codecs
#init
{
    addCodec'CodecPcmToPcm16()
}

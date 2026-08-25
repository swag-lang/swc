//! Format: Format-neutral sound codec registry.
//! Supported: Incremental and packet decoder registration, lookup, lifecycle, packet framing queries, and byte-progress reporting.
//! Not supported: This file does not decode or encode a concrete sound format.
//! Role: This file owns the common codec contracts and registry used by concrete codec subfolders.
//
using Core, Core.Errors

var g_Codecs:       Array'CodecDesc
var g_PacketCodecs: Array'PacketCodecDesc

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
    mtd initialize(source: const [*] void, sourceSize: u64)->u64 fail

    // Decodes one chunk and reports produced and consumed byte counts.
    //
    // At most `destinationSize` bytes may be written to `destination`, and at most
    // `sourceSize` bytes may be read from `source`.
    mtd decode(destination: [*] void, destinationSize: u64, source: const [*] void, sourceSize: u64)->CodecProgress fail
}

// Decodes independently indexed compressed access units to interleaved PCM16.
//
// Packet codecs are used by container readers such as MP4. One instance belongs to one
// voice, so implementations may retain overlap, prediction, and filter state between calls.
public interface IPacketCodec
{
    // Returns whether this codec can consume `encoding`.
    mtd canDecode(encoding: SoundFileEncoding)->bool

    // Initializes codec state from the container's decoder configuration.
    mtd initialize(config: const [..] u8, sampleRateHz, channels: u32) fail

    // Restores the state used before the first access unit.
    mtd reset()

    // Decodes one complete access unit to interleaved PCM16 and returns bytes written.
    mtd decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
}

// Reports whether `encoding` names packets a packet codec decodes.
//
// A packetized sound is one whose payload is a sequence of independently indexed compressed
// access units; the uncompressed encodings are chunked instead, and go through the PCM path.
public func isPacketEncoding(encoding: SoundFileEncoding)->bool
{
    switch encoding
    {
    case .AacLc, .Ac3, .Eac3, .Flac, .Mp3:
        return true
    default:
        return false
    }
}

// Returns the number of sample frames one packet of `encoding` decodes to.
//
// A container builds its packet index before any decoding happens, so this reads the count out
// of the packet header rather than decoding the packet. `packet` needs to hold the header only,
// not the whole access unit.
public func packetFrameCount(encoding: SoundFileEncoding, packet: const [..] u8)->u32 fail
{
    switch encoding
    {
    case .AacLc:
        return 1024
    case .Ac3:
        return try Dolby.ac3PacketFrameCount(packet)
    case .Eac3:
        return try Dolby.eac3PacketFrameCount(packet)
    case .Flac:
        return try Flac.packetFrameCount(packet)
    case .Mp3:
        return try Mp3.packetFrameCount(packet)
    default:
        fail UnsupportedFormatError{"unsupported packetized sound encoding"}
    }
}

// Reports the byte-level progress of one incremental codec operation.
public struct CodecProgress
{
    public
    {
        bytesWritten: u64     // Bytes produced in the destination buffer.
        bytesRead:    u64     // Bytes consumed from the source buffer.
    }
}

struct CodecDesc
{
    type: const *Swag.TypeInfoStruct
    itf:  ICodec
}

struct PacketCodecDesc
{
    type: const *Swag.TypeInfoStruct
    itf:  IPacketCodec
}

// Reports whether `type` opens with the registry header every codec instance is destroyed through.
//
// A voice allocates a codec by its type, hands the caller an interface, and later reads the
// concrete type and the allocator back out of the first bytes of the instance. A codec that does
// not start with [[Audio.Codec]] therefore destroys something else, and nothing says so until the
// process faults inside the destructor.
#[Swag.ConstExpr]
private func startsWithCodecHeader(type: const *Swag.TypeInfoStruct)->bool
{
    for field in type.fields
    {
        if field.offset != 0 or !field.pointedType do
            continue
        if field.pointedType!.crc == #typeof(Codec).crc do
            return true
    }

    return false
}

// Registers a codec implementation for subsequent voice creation.
//
// `T` must implement [[Audio.ICodec]]. Registration stores its type and
// interface dispatch table; codec instances are allocated on demand.
public func(T) registerCodec()
{
    #assert(Reflection.hasInterface(#typeof(T), ICodec))
    #assert(startsWithCodecHeader(#typeof(T)))

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

// Registers a packet codec implementation for subsequent voice creation.
//
// `T` must implement [[Audio.IPacketCodec]]. Registration stores its type and
// interface dispatch table; codec instances are allocated on demand.
public func(T) registerPacketCodec()
{
    #assert(Reflection.hasInterface(#typeof(T), IPacketCodec))
    #assert(startsWithCodecHeader(#typeof(T)))

    registerPacketCodecImplementation(#typeof(T), @mkinterface(null, #typeof(T), IPacketCodec))
}

// Non-generic bridge used by registerPacketCodec after its body is instantiated in the
// caller's module.
#[Swag.NoDoc]
public func registerPacketCodecImplementation(type: const *Swag.TypeInfoStruct, itf: IPacketCodec)
{
    var desc: PacketCodecDesc = undefined
    desc.type = type
    desc.itf  = itf
    g_PacketCodecs.add(desc)
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

func findPacketCodec(sourceEncoding: SoundFileEncoding)->#null *PacketCodecDesc
{
    for &codec in g_PacketCodecs where codec.itf.canDecode(sourceEncoding) do
        return codec
    return null
}

// Stores the source, destination, and concrete type of a codec instance.
public struct Codec
{
    public readonly
    {
        sourceEncoding:      SoundFileEncoding     // Encoding read from the sound file.
        destinationEncoding: SoundFileEncoding     // Encoding requested by the active backend.
    }

    internal
    {
        // Concrete codec type used for destruction.
        #[Swag.Late]
        type:                const *Swag.TypeInfoStruct
        allocationAllocator: IAllocator = undefined
    }
}

impl Codec
{
    mtd configure(sourceEncoding, destinationEncoding: SoundFileEncoding, type: const *Swag.TypeInfoStruct, allocator: IAllocator)
    {
        .sourceEncoding      = sourceEncoding
        .destinationEncoding = destinationEncoding
        .type                = type
        .allocationAllocator = allocator
    }
}

// Initialize predefined codecs
#init
{
    registerCodec'CodecPcmToPcm16()
}

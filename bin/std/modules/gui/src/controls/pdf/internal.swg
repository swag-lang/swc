#global namespace Pdf

using Core, Pixel

const InvalidNode = Swag.U32.Max

enum NodeKind
{
    Null
    Boolean
    Integer
    Real
    Name
    String
    Array
    Dictionary
    Reference
}

struct Node
{
    kind:      NodeKind
    integer:   s64
    real:      f64
    boolean:   bool
    text:      String
    values:    Array'u32
    entries:   HashTable'(String, u32)
    reference: u32
    stream:    Array'u8

    // Generation of an indirect reference. Two objects may carry the same number with
    // different generations, and only the pair names one of them.
    referenceGeneration: u16
}

// Where the cross-reference index says one object is written.
enum XrefKind
{
    Free         // A hole: the number names no object in this revision.
    Offset       // Written in the file, at a byte offset from the header.
    InStream     // Written inside a compressed object stream.
}

struct XrefEntry
{
    kind:          XrefKind
    offset:        u64     // Offset form: where `N G obj` starts.
    container:     u32     // Stream form: object number of the containing object stream.
    indexInStream: u32     // Stream form: position of the object inside that stream.
    generation:    u16
}

// One expanded object stream, kept so the objects sharing it are decompressed once.
//
// The pointer handed out must stay valid while an object is parsed out of it, and parsing one
// object can pull another stream in, so these live in an ArrayPtr rather than in the table.
struct ObjectStream
{
    data:    Array'u8
    numbers: Array'u32
    offsets: Array'u64
    first:   u64
}

struct PdfParser
{
    bytes:   const [..] u8 = cast(const [..] u8) ""
    pos:     u64
    nodes:   Array'Node
    objects: HashTable'(u32, u32)

    // Filled by the trailer scan: the catalog and metadata dictionaries the file itself
    // names, and whether it declares a security handler.
    trailerRoot: u32 = InvalidNode
    trailerInfo: u32 = InvalidNode
    isEncrypted: bool

    // Where each object lives, from the file's own cross-reference chain, and how deep the
    // lazy parse currently is. An object is parsed the first time something asks for it, and
    // `objects` is where the parsed node is remembered.
    xref:         HashTable'(u32, XrefEntry)
    objectDepth:  u32
    hasScanned:   bool

    objectStreams:     ArrayPtr'ObjectStream
    objectStreamIndex: HashTable'(u32, u32)

    // Images already decoded from this document, keyed by the image object together with the
    // resource dictionary that resolved its color space.
    //
    // A slide deck paints its template on every page and a report repeats its letterhead, so the
    // same object is asked for once per page that shows it. Decoding it again each time is the
    // single largest cost of walking such a document, and the result is byte-identical every
    // time. The pair is the key because a named color space is defined by the resources in
    // force, so the same object under different resources is not the same image.
    imageCache:      HashTable'(u64, Image)
    imageCacheBytes: u64

    // Fonts already decoded from this document, keyed by the font object.
    //
    // Every page that names a font decodes it again otherwise, which decompresses the same
    // embedded program, rebuilds the same encoding and width tables, and leaves each page
    // holding its own copy of the bytes: a hundred-page thesis with a four-hundred-kilobyte
    // family carries forty megabytes of duplicated font data.
    fontCache: HashTable'(u32, FontResource)
}

// How much decoded image data one document keeps.
//
// The cache exists to stop a repeated image being decoded once per page, not to hold a whole
// document's rasters: past this, a document with many distinct large images would trade an
// unbounded amount of memory for pages it has already left behind.
const ImageCacheBudget = 64 * 1024 * 1024'u64

// Returns the cache key of one decoded image.
func imageCacheKey(imageId, resourcesId: u32)->u64 => (cast(u64) imageId << 32) | cast(u64) resourcesId

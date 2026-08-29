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

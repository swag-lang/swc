using Core

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
    bytes:   const [..] u8
    pos:     u64
    nodes:   Array'Node
    objects: HashTable'(u32, u32)

    // Filled by the trailer scan: the catalog and metadata dictionaries the file itself
    // names, and whether it declares a security handler.
    trailerRoot: u32 = InvalidNode
    trailerInfo: u32 = InvalidNode
    isEncrypted: bool
}

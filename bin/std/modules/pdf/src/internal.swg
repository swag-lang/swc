using Core, Core.Math, Pixel

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

// Internal page storage whose type identity is part of the exported Page layout.
#[Swag.NoDoc]
public struct FontResource
{
    objectId:  u32
    name:      String
    baseName:  String
    bytes:     Array'u8
    unicode:   HashTable'(u32, String)
    codeBytes: u32 = 1
}

struct PdfParser
{
    bytes:   const [..] u8
    pos:     u64
    nodes:   Array'Node
    objects: HashTable'(u32, u32)
}

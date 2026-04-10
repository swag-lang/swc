#global fileprivate

#[Swag.Pack(1)]
struct Packed1
{
    a: u8
    b: u32
}

#[Swag.Pack(2)]
struct Packed2
{
    a: u8
    b: u32
}

#[Swag.Pack(4)]
struct Packed4
{
    a: u8
    b: u64
}

#[Swag.Align(8)]
struct StructAlign8
{
    a: bool
    b: bool
}

struct FieldAlign8
{
    a: bool
    #[Swag.Align(8)]
    b: bool
}

#[Swag.Align(8)]
struct MixedAlign
{
    a: bool
    #[Swag.Align(4)]
    b: bool
}

struct OverlayScalar
{
    x: s32
    #[Swag.Offset("x")]
    y: s32
}

struct OverlayArray
{
    x, y, z: f32
    #[Swag.Offset("x")]
    idx: [3] f32
}

#test
{
    #assert(#offsetof(Packed1.a) == 0)
    #assert(#offsetof(Packed1.b) == 1)
    #assert(#sizeof(Packed1) == 5)

    #assert(#offsetof(Packed2.a) == 0)
    #assert(#offsetof(Packed2.b) == 2)
    #assert(#sizeof(Packed2) == 6)

    #assert(#offsetof(Packed4.a) == 0)
    #assert(#offsetof(Packed4.b) == 4)
    #assert(#sizeof(Packed4) == 12)

    #assert(#offsetof(StructAlign8.a) == 0)
    #assert(#offsetof(StructAlign8.b) == 1)
    #assert(#sizeof(StructAlign8) == 8)

    #assert(#offsetof(FieldAlign8.a) == 0)
    #assert(#offsetof(FieldAlign8.b) == 8)
    #assert(#sizeof(FieldAlign8) == 16)

    #assert(#offsetof(MixedAlign.a) == 0)
    #assert(#offsetof(MixedAlign.b) == 4)
    #assert(#sizeof(MixedAlign) == 8)

    #assert(#offsetof(OverlayScalar.x) == 0)
    #assert(#offsetof(OverlayScalar.y) == 0)
    #assert(#sizeof(OverlayScalar) == 4)

    #assert(#offsetof(OverlayArray.x) == 0)
    #assert(#offsetof(OverlayArray.y) == 4)
    #assert(#offsetof(OverlayArray.z) == 8)
    #assert(#offsetof(OverlayArray.idx) == 0)
    #assert(#sizeof(OverlayArray) == 12)

    var overlay = OverlayScalar{}
    overlay.x = 666
    @assert(overlay.y == 666)
    overlay.y = 42
    @assert(overlay.x == 42)

    var indexed: OverlayArray
    indexed.x = 10
    indexed.y = 20
    indexed.z = 30
    @assert(indexed.idx[0] == indexed.x)
    @assert(indexed.idx[1] == indexed.y)
    @assert(indexed.idx[2] == indexed.z)
    indexed.idx[1] = 77
    @assert(indexed.y == 77)
}

#global fileprivate

struct A
{
    a: u32
    b: u32
}

#assert(#sizeof(A) == 8)

struct B
{
    a: u32
#if false {
    b: u32
}
}

#assert(#sizeof(B) == 4)
#assert(#offsetof(B.a) == 0)

#assert(#offsetof(A.a) == 0)
#assert(#offsetof(A.b) == 4)

struct C
{
    a: u8
    b: u32
    c: u8
}

#assert(#offsetof(C.a) == 0)
#assert(#offsetof(C.b) == 4) // 3 bytes of padding after a
#assert(#offsetof(C.c) == 8)
#assert(#sizeof(C) == 12)   // padded to multiple of 4

struct D
{
    a: u32
    b: u8
    c: u8
}

#assert(#offsetof(D.a) == 0)
#assert(#offsetof(D.b) == 4)
#assert(#offsetof(D.c) == 5)
#assert(#sizeof(D) == 8)    // tail padding to alignment of 4

struct Inner
{
    x: u32
    y: u32
}

struct Outer
{
    a: u32
    b: Inner
    c: u32
}

#assert(#sizeof(Inner) == 8)
#assert(#offsetof(Inner.x) == 0)
#assert(#offsetof(Inner.y) == 4)

#assert(#offsetof(Outer.a) == 0)
#assert(#offsetof(Outer.b) == 4)
#assert(#offsetof(Outer.c) == 12)
#assert(#sizeof(Outer) == 16)

struct E
{
    a: u32
}

#assert(#offsetof(E.a) == 0)

struct F
{
    a: u32
#if false {
    mid: u32
}
    b: u32
}

#assert(#offsetof(F.a) == 0)
#assert(#offsetof(F.b) == 4)
#assert(#sizeof(F) == 8)

#[Swag.Pack(1)]
struct Packed1
{
    a: u8
    b: u32
}

#assert(#offsetof(Packed1.a) == 0)
#assert(#offsetof(Packed1.b) == 1)
#assert(#sizeof(Packed1) == 5)

#[Swag.Pack(2)]
struct Packed2
{
    a: u8
    b: u32
}

#assert(#offsetof(Packed2.a) == 0)
#assert(#offsetof(Packed2.b) == 2)
#assert(#sizeof(Packed2) == 6)

#[Swag.Pack(4)]
struct Packed4
{
    a: u8
    b: u64
}

#assert(#offsetof(Packed4.a) == 0)
#assert(#offsetof(Packed4.b) == 4)
#assert(#sizeof(Packed4) == 12)

#[Swag.Align(8)]
struct StructAlign8
{
    a: bool
    b: bool
}

#assert(#offsetof(StructAlign8.a) == 0)
#assert(#offsetof(StructAlign8.b) == 1)
#assert(#sizeof(StructAlign8) == 8)

struct FieldAlign8
{
    a: bool
    #[Swag.Align(8)]
    b: bool
}

#assert(#offsetof(FieldAlign8.a) == 0)
#assert(#offsetof(FieldAlign8.b) == 8)
#assert(#sizeof(FieldAlign8) == 16)

#[Swag.Align(8)]
struct MixedAlign
{
    a: bool
    #[Swag.Align(4)]
    b: bool
}

#assert(#offsetof(MixedAlign.a) == 0)
#assert(#offsetof(MixedAlign.b) == 4)
#assert(#sizeof(MixedAlign) == 8)

struct OverlayScalar
{
    x: s32
    #[Swag.Offset("x")]
    y: s32
}

#assert(#offsetof(OverlayScalar.x) == 0)
#assert(#offsetof(OverlayScalar.y) == 0)
#assert(#sizeof(OverlayScalar) == 4)

struct OverlayArray
{
    x, y, z: f32
    #[Swag.Offset("x")]
    idx: [3] f32
}

#assert(#offsetof(OverlayArray.x) == 0)
#assert(#offsetof(OverlayArray.y) == 4)
#assert(#offsetof(OverlayArray.z) == 8)
#assert(#offsetof(OverlayArray.idx) == 0)
#assert(#sizeof(OverlayArray) == 12)

struct CC
{
    a: *CC
}

struct EE
{
    a: CC
    b: u32
}
#assert(#sizeof(EE) == #sizeof(CC) + #sizeof(u64))

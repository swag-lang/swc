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
}

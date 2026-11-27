#global private

#[Swag.Pack(1)]
struct Packed3
{
    a: u8
    b: u16
}

#[Swag.Pack(1)]
struct Packed5
{
    a: u8
    b: u32
}

func makePacked3(a: u8, b: u16)->Packed3
{
    return {a: a, b: b}
}

func makePacked5(a: u8, b: u32)->Packed5
{
    return {a: a, b: b}
}

#test
{
    #assert(#sizeof(Packed3) == 3)
    #assert(#sizeof(Packed5) == 5)
}

#test
{
    func sumPacked3(values: Packed3...)->u32
    {
        return cast(u32, values[0].a) +
               cast(u32, values[0].b) +
               cast(u32, values[1].a) +
               cast(u32, values[1].b) +
               cast(u32, values[2].a) +
               cast(u32, values[2].b)
    }

    const value = #run sumPacked3(
        makePacked3(1_u8, 0x0203_u16),
        makePacked3(4_u8, 0x0506_u16),
        makePacked3(7_u8, 0x0809_u16))
    #assert(value == 0x0203_u32 + 1_u32 + 0x0506_u32 + 4_u32 + 0x0809_u32 + 7_u32)
}

#test
{
    func sumPacked5(values: Packed5...)->u64
    {
        return cast(u64, values[0].a) +
               cast(u64, values[0].b) +
               cast(u64, values[1].a) +
               cast(u64, values[1].b)
    }

    const value = #run sumPacked5(
        makePacked5(0x11_u8, 0x22334455_u32),
        makePacked5(0x66_u8, 0x778899AA_u32))
    #assert(value == 0x11_u64 + 0x22334455_u64 + 0x66_u64 + 0x778899AA_u64)
}

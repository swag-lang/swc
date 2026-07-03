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
        return cast(u32) values[0].a +
               cast(u32) values[0].b +
               cast(u32) values[1].a +
               cast(u32) values[1].b +
               cast(u32) values[2].a +
               cast(u32) values[2].b
    }

    const value = #run sumPacked3(
        makePacked3(1'u8, 0x0203'u16),
        makePacked3(4'u8, 0x0506'u16),
        makePacked3(7'u8, 0x0809'u16))
    #assert(value == 0x0203'u32 + 1'u32 + 0x0506'u32 + 4'u32 + 0x0809'u32 + 7'u32)
}

#test
{
    func sumPacked5(values: Packed5...)->u64
    {
        return cast(u64) values[0].a +
               cast(u64) values[0].b +
               cast(u64) values[1].a +
               cast(u64) values[1].b
    }

    const value = #run sumPacked5(
        makePacked5(0x11'u8, 0x22334455'u32),
        makePacked5(0x66'u8, 0x778899AA'u32))
    #assert(value == 0x11'u64 + 0x22334455'u64 + 0x66'u64 + 0x778899AA'u64)
}

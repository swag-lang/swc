#global private

#[Swag.NoInline] func between32(value, low, high: u32)->u32 => value >= low and value <= high ? 1 : 0
#[Swag.NoInline] func outsideGap32(value, low, high: u32)->u32 => value <= low and value >= high ? 1 : 0
#[Swag.NoInline] func between64(value, low, high: u64)->u64 => value >= low and value <= high ? 1 : 0
#[Swag.NoInline] func betweenSigned(value, low, high: s32)->u32 => value >= low and value <= high ? 1 : 0

#test
{
    let values = [0'u64, 1, 7, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for value in values do for low in values do for high in values
    {
        Swag.assert(between64(value, low, high) == (value >= low and value <= high ? 1 : 0))

        let value32 = cast(u32) value
        let low32 = cast(u32) low
        let high32 = cast(u32) high
        Swag.assert(between32(value32, low32, high32) == (value32 >= low32 and value32 <= high32 ? 1 : 0))
        Swag.assert(outsideGap32(value32, low32, high32) == (value32 <= low32 and value32 >= high32 ? 1 : 0))

        let valueSigned = cast(s32) value32
        let lowSigned = cast(s32) low32
        let highSigned = cast(s32) high32
        Swag.assert(betweenSigned(valueSigned, lowSigned, highSigned) == (valueSigned >= lowSigned and valueSigned <= highSigned ? 1 : 0))
    }
}

#global fileprivate

#test
{
    func unsignedToFloatCasts()->bool
    {
        let small32 = cast(f32) 45'u32
        let max32 = cast(f32) Swag.U32.Max
        let max64 = cast(f64) Swag.U64.Max

        return small32 == 45.0'f32 and
               max32 > 4_000_000_000.0'f32 and
               max32 < 4_300_000_000.0'f32 and
               max64 > 18_000_000_000_000_000_000.0'f64 and
               max64 < 19_000_000_000_000_000_000.0'f64
    }

    const V = #run unsignedToFloatCasts()
    #assert(V)
}

#test
{
    func subtractMixed(value: f32, base: s32)->f32
    {
        return value - base
    }

    func addMixed(value: f32, delta: u16)->f32
    {
        return value + delta
    }

    const SUB = #run subtractMixed(1.25'f32, 1)
    const ADD = #run addMixed(1.5'f32, 2'u16)
    #assert(SUB > 0.24'f32 and SUB < 0.26'f32)
    #assert(ADD > 3.49'f32 and ADD < 3.51'f32)
}

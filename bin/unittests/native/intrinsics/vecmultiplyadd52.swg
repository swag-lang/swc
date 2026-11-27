private alias U64x2 = #simd [2] u64

#test
{
    if not Swag.hasCpuFeature(.MultiplyAdd52)
    {
        return

    }
    const Base = 1_u64 << 52
    let left        = cast(U64x2, [Base + 3, Swag.U64.Max])
    let right       = cast(U64x2, [2_u64, Base - 1])
    let accumulator = cast(U64x2, [Swag.U64.Max - 1, 4_u64])
    let low         = cast([2] u64, Swag.vecMultiplyAdd52Low(accumulator, left, right))
    let high        = cast([2] u64, Swag.vecMultiplyAdd52High(accumulator, left, right))
    Swag.require(low[0] == 4 and low[1] == 5)
    Swag.require(high[0] == Swag.U64.Max - 1 and high[1] == Base + 2)
}

struct(T) Cell
{
    value: T
}

impl Cell
{
    func doubled(me)->T => .value + .value
}

var total: s64

#[Swag.NoInline]
func(T) accumulate(value: T)
{
    let cell: Cell!{T} = {value: value}
    total += cast(s64, cell.doubled())
}

#main
{
    accumulate(1_s8)
    accumulate(2_s16)
    accumulate(3_s32)
    accumulate(4_s64)
    accumulate(5_u8)
    accumulate(6_u16)
    accumulate(7_u32)
    accumulate(8_u64)
    Swag.assert(total == 72)
    Swag.print("internal-link-benchmark-ok\n")
}

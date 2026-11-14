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
    let cell: Cell'T = {value: value}
    total += cast(s64, cell.doubled())
}

#main
{
    accumulate(1's8)
    accumulate(2's16)
    accumulate(3's32)
    accumulate(4's64)
    accumulate(5'u8)
    accumulate(6'u16)
    accumulate(7'u32)
    accumulate(8'u64)
    Swag.assert(total == 72)
    Swag.print("internal-link-benchmark-ok\n")
}

#[Swag.NoInline]
func multiply(left, right: u64, high: *u64)->u64 => Swag.mulWide(left, right, high)

#test
{
    var high: u64
    let maxProduct = multiply(Swag.U64.Max, Swag.U64.Max, &high)
    Swag.require(maxProduct == 1 and high == Swag.U64.Max - 1)

    let exactCarry = multiply(0x8000000000000000'u64, 2, &high)
    Swag.require(exactCarry == 0 and high == 1)

    let lowOnly = multiply(65535, 65535, &high)
    Swag.require(lowOnly == 4294836225 and high == 0)

    let zero = multiply(0, Swag.U64.Max, &high)
    Swag.require(zero == 0 and high == 0)
}

#test
{
    var left = Swag.U64.Max
    let low  = Swag.mulWide(left, 3, &left)
    Swag.require(low == Swag.U64.Max - 2 and left == 2)

    var high = 1'u64
    discard Swag.mulWide(0, 12, &high)
    Swag.require(high == 0)
}

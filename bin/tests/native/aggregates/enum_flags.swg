#global fileprivate // 

#[Swag.EnumFlags]
enum TestFlags: u32
{
    A,
    B,
    C,
}

#test
{
    var value   = TestFlags.A | TestFlags.B
    var masked  = value & TestFlags.B
    var missing = value & TestFlags.C
    var toggled = value ^ TestFlags.B

    @assert(cast(u32) value == 3)
    @assert(masked == TestFlags.B)
    @assert(cast(u32) missing == 0)
    @assert(toggled == TestFlags.A)
}

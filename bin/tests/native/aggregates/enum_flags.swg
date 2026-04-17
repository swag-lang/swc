#global fileprivate // 

#[Swag.EnumFlags]
enum TestFlags: u32
{
    A,
    B,
    C,
    AB = A | B,
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
    @assert(TestFlags.AB == (TestFlags.A | TestFlags.B))
    @assert((TestFlags.AB & TestFlags.B) == TestFlags.B)
}

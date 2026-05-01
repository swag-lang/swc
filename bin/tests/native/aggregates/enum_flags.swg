#global fileprivate // 

#[Swag.EnumFlags]
enum TestFlags: u32
{
    A,
    B,
    C,
    AB = A | B,
}

#[Swag.Strict]
alias StrictTestFlags = TestFlags

func boxStrictTestFlags(value: StrictTestFlags)->bool
{
    let boxed: any = value
    return @kindof(boxed) == StrictTestFlags and cast(StrictTestFlags) boxed == value
}

func makeStrictTestFlag()->StrictTestFlags
{
    return cast(StrictTestFlags) TestFlags.B
}

func makeStrictTestFlagArray()->[2] StrictTestFlags
{
    return [cast(StrictTestFlags) TestFlags.A, cast(StrictTestFlags) TestFlags.C]
}

func runtimeStrictTestFlagArray()->bool
{
    let values = makeStrictTestFlagArray()
    return values[0] == cast(StrictTestFlags) TestFlags.A and values[1] == cast(StrictTestFlags) TestFlags.C
}

func runtimeStrictTestFlagArrayFirstRaw()->u32
{
    let values = makeStrictTestFlagArray()
    return cast(u32) values[0]
}

func runtimeStrictTestFlagArraySecondRaw()->u32
{
    let values = makeStrictTestFlagArray()
    return cast(u32) values[1]
}

func invertStrictTestFlags(value: StrictTestFlags)->StrictTestFlags
{
    return ~value
}

const RunStrictTestFlag: StrictTestFlags = #run makeStrictTestFlag()
const RunStrictTestFlags: [2] StrictTestFlags = #run makeStrictTestFlagArray()

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

#test
{
    var value = cast(StrictTestFlags) TestFlags.A | cast(StrictTestFlags) TestFlags.B
    var masked = value & cast(StrictTestFlags) TestFlags.B
    var missing = value & cast(StrictTestFlags) TestFlags.C
    var toggled = value ^ cast(StrictTestFlags) TestFlags.B
    var inverted = ~cast(StrictTestFlags) TestFlags.C

    #assert(#typeof(value) == StrictTestFlags)
    #assert(#typeof(inverted) == StrictTestFlags)
    @assert(cast(u32) value == 3)
    @assert(masked == cast(StrictTestFlags) TestFlags.B)
    @assert(cast(u32) missing == 0)
    @assert(toggled == cast(StrictTestFlags) TestFlags.A)
    @assert((cast(u32) inverted & cast(u32) TestFlags.A) != 0)
    @assert(cast(bool) value)
    @assert(!cast(bool) missing)

    var assigned = cast(StrictTestFlags) TestFlags.A
    assigned |= cast(StrictTestFlags) TestFlags.B
    @assert(cast(u32) assigned == 3)
    assigned &= cast(StrictTestFlags) TestFlags.A
    @assert(assigned == cast(StrictTestFlags) TestFlags.A)
    assigned ^= cast(StrictTestFlags) TestFlags.C
    @assert(cast(u32) assigned == 5)

    const boxed: any = cast(StrictTestFlags) TestFlags.B
    @assert(@kindof(boxed) == StrictTestFlags)
    @assert(cast(StrictTestFlags) boxed == cast(StrictTestFlags) TestFlags.B)
    @assert(boxStrictTestFlags(cast(StrictTestFlags) TestFlags.C))
    @assert(runtimeStrictTestFlagArrayFirstRaw() == 1)
    @assert(runtimeStrictTestFlagArraySecondRaw() == 4)
    @assert(runtimeStrictTestFlagArray())
    @assert(RunStrictTestFlag == cast(StrictTestFlags) TestFlags.B)
    @assert(RunStrictTestFlags[0] == cast(StrictTestFlags) TestFlags.A)
    @assert(RunStrictTestFlags[1] == cast(StrictTestFlags) TestFlags.C)

    let runtimeInverted = invertStrictTestFlags(cast(StrictTestFlags) TestFlags.C)
    #assert(#typeof(runtimeInverted) == StrictTestFlags)
    @assert((cast(u32) runtimeInverted & cast(u32) TestFlags.A) != 0)
}

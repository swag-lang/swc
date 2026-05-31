#global fileprivate

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

#[Swag.EnumFlags]
enum RefTestFlags: u32
{
    Zero = 0,
    A,
    B,
    C,
    D,
}

struct RefTestFlagBuffer
{
    values: [2] RefTestFlags
}

impl RefTestFlagBuffer
{
    mtd refAt(index: u64)->&RefTestFlags { return &me.values[index] }
}

#[Swag.EnumFlags]
enum ImplicitRefTestFlags
{
    Zero = 0,
    West,
    East,
    North,
    South,
}

struct ImplicitRefTestFlagBuffer
{
    values: [2] ImplicitRefTestFlags
}

impl ImplicitRefTestFlagBuffer
{
    mtd refAt(index: u64)->&ImplicitRefTestFlags { return &me.values[index] }
}

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

#test
{
    var values: RefTestFlagBuffer
    let firstRef = #ref values.refAt(0)
    firstRef = RefTestFlags.A | RefTestFlags.B
    values.values[0] = RefTestFlags.A | RefTestFlags.B
    values.values[1] = RefTestFlags.B | RefTestFlags.C

    values.refAt(0) &= ~RefTestFlags.A
    @assert(values.values[0] == RefTestFlags.B)

    let valueRef = #ref values.refAt(1)
    valueRef |= RefTestFlags.D
    @assert(values.values[1] == (RefTestFlags.B | RefTestFlags.C | RefTestFlags.D))
}

#test
{
    var values: [2] RefTestFlags

    #[Swag.Mixin]
    func refAt(index: u64)->&RefTestFlags => &values[index]

    let firstRef = #ref refAt(0)
    firstRef = RefTestFlags.A | RefTestFlags.B
    @assert(values[0] == (RefTestFlags.A | RefTestFlags.B))
}

#test
{
    var values: ImplicitRefTestFlagBuffer
    values.values[0] = .West | .East
    values.values[1] = .North | .South

    var tookEast = false
    let horizontal = values.refAt(0)
    switch
    {
    case horizontal & .East:
        tookEast = true
    }

    var tookSouth = false
    if values.refAt(1) & .South do
        tookSouth = true

    var missingWest = false
    if !(values.refAt(1) & .West) do
        missingWest = true

    values.refAt(0) &= ~.West

    @assert(tookEast)
    @assert(tookSouth)
    @assert(missingWest)
    @assert(values.values[0] == .East)
}

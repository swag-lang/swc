#global private

#[Swag.EnumFlags]
enum TestFlags: u32
{
    A,
    B,
    C,
    AB = A | B
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
    D
}

struct RefTestFlagBuffer
{
    values: [2] RefTestFlags
}

impl RefTestFlagBuffer
{
    mtd refAt(index: u64)->*RefTestFlags { return &me.values[index] }
}

#[Swag.EnumFlags]
enum ImplicitRefTestFlags
{
    Zero = 0,
    West,
    East,
    North,
    South
}

struct ImplicitRefTestFlagBuffer
{
    values: [2] ImplicitRefTestFlags
}

impl ImplicitRefTestFlagBuffer
{
    mtd refAt(index: u64)->*ImplicitRefTestFlags { return &me.values[index] }
}

func boxStrictTestFlags(value: StrictTestFlags)->bool
{
    let boxed: any = value
    return Swag.kindOf(boxed) == StrictTestFlags and assume cast(StrictTestFlags, boxed) == value
}

func makeStrictTestFlag()->StrictTestFlags
{
    return cast(StrictTestFlags, TestFlags.B)
}

func makeStrictTestFlagArray()->[2] StrictTestFlags
{
    return [cast(StrictTestFlags, TestFlags.A), cast(StrictTestFlags, TestFlags.C)]
}

func runtimeStrictTestFlagArray()->bool
{
    let values = makeStrictTestFlagArray()
    return values[0] == cast(StrictTestFlags, TestFlags.A) and values[1] == cast(StrictTestFlags, TestFlags.C)
}

func runtimeStrictTestFlagArrayFirstRaw()->u32
{
    let values = makeStrictTestFlagArray()
    return cast(u32, values[0])
}

func runtimeStrictTestFlagArraySecondRaw()->u32
{
    let values = makeStrictTestFlagArray()
    return cast(u32, values[1])
}

func invertStrictTestFlags(value: StrictTestFlags)->StrictTestFlags
{
    return ~value
}

func(T) pickGenericFlags(flags: T, value: T)->T
{
    return flags | value
}

const RunStrictTestFlag:  StrictTestFlags     = #run makeStrictTestFlag()
const RunStrictTestFlags: [2] StrictTestFlags = #run makeStrictTestFlagArray()

#test
{
    var value   = TestFlags.A | TestFlags.B
    var masked  = value & TestFlags.B
    var missing = value & TestFlags.C
    var toggled = value ^ TestFlags.B

    Swag.require(cast(u32, value) == 3)
    Swag.require(masked == TestFlags.B)
    Swag.require(cast(u32, missing) == 0)
    Swag.require(toggled == TestFlags.A)
    Swag.require(TestFlags.AB == (TestFlags.A | TestFlags.B))
    Swag.require((TestFlags.AB & TestFlags.B) == TestFlags.B)
}

#test
{
    var value    = cast(StrictTestFlags, TestFlags.A) | cast(StrictTestFlags, TestFlags.B)
    var masked   = value & cast(StrictTestFlags, TestFlags.B)
    var missing  = value & cast(StrictTestFlags, TestFlags.C)
    var toggled  = value ^ cast(StrictTestFlags, TestFlags.B)
    var inverted = ~cast(StrictTestFlags, TestFlags.C)

    #assert(#typeof(value) == StrictTestFlags)
    #assert(#typeof(inverted) == StrictTestFlags)
    Swag.require(cast(u32, value) == 3)
    Swag.require(masked == cast(StrictTestFlags, TestFlags.B))
    Swag.require(cast(u32, missing) == 0)
    Swag.require(toggled == cast(StrictTestFlags, TestFlags.A))
    Swag.require((cast(u32, inverted) & cast(u32, TestFlags.A)) != 0)
    Swag.require(cast(bool, value))
    Swag.require(not cast(bool, missing))

    var assigned = cast(StrictTestFlags, TestFlags.A)
    assigned |= cast(StrictTestFlags, TestFlags.B)
    Swag.require(cast(u32, assigned) == 3)
    assigned &= cast(StrictTestFlags, TestFlags.A)
    Swag.require(assigned == cast(StrictTestFlags, TestFlags.A))
    assigned ^= cast(StrictTestFlags, TestFlags.C)
    Swag.require(cast(u32, assigned) == 5)

    const boxed: any = cast(StrictTestFlags, TestFlags.B)
    Swag.require(Swag.kindOf(boxed) == StrictTestFlags)
    Swag.require(assume cast(StrictTestFlags, boxed) == cast(StrictTestFlags, TestFlags.B))
    Swag.require(boxStrictTestFlags(cast(StrictTestFlags, TestFlags.C)))
    Swag.require(runtimeStrictTestFlagArrayFirstRaw() == 1)
    Swag.require(runtimeStrictTestFlagArraySecondRaw() == 4)
    Swag.require(runtimeStrictTestFlagArray())
    Swag.require(RunStrictTestFlag == cast(StrictTestFlags, TestFlags.B))
    Swag.require(RunStrictTestFlags[0] == cast(StrictTestFlags, TestFlags.A))
    Swag.require(RunStrictTestFlags[1] == cast(StrictTestFlags, TestFlags.C))

    let runtimeInverted = invertStrictTestFlags(cast(StrictTestFlags, TestFlags.C))
    #assert(#typeof(runtimeInverted) == StrictTestFlags)
    Swag.require((cast(u32, runtimeInverted) & cast(u32, TestFlags.A)) != 0)
}

#test
{
    let flags = TestFlags.A
    let value = flags.pickGenericFlags(.B | .C)

    #assert(#typeof(value) == TestFlags)
    Swag.require(value == (TestFlags.A | TestFlags.B | TestFlags.C))
}

#test
{
    var values:   RefTestFlagBuffer
    let firstRef: *RefTestFlags = values.refAt(0)
    firstRef[]       = RefTestFlags.A | RefTestFlags.B
    values.values[0] = RefTestFlags.A | RefTestFlags.B
    values.values[1] = RefTestFlags.B | RefTestFlags.C

    values.refAt(0)[] &= ~RefTestFlags.A
    Swag.require(values.values[0] == RefTestFlags.B)

    let valueRef: *RefTestFlags = values.refAt(1)
    valueRef[] |= RefTestFlags.D
    Swag.require(values.values[1] == (RefTestFlags.B | RefTestFlags.C | RefTestFlags.D))
}

#test
{
    var values: [2] RefTestFlags

    #[Swag.Mixin]
    func refAt(index: u64)->*RefTestFlags => &values[index]

    let firstRef: *RefTestFlags = refAt(0)
    firstRef[] = RefTestFlags.A | RefTestFlags.B
    Swag.require(values[0] == (RefTestFlags.A | RefTestFlags.B))
}

#test
{
    var values: ImplicitRefTestFlagBuffer
    values.values[0] = .West | .East
    values.values[1] = .North | .South

    var tookEast   = false
    let horizontal = values.refAt(0)
    switch
    {
    case horizontal[] & .East:
        tookEast = true
    }

    var tookSouth = false
    if values.refAt(1)[] & .South do
        tookSouth = true

    var missingWest = false
    if not (values.refAt(1)[] & .West) do
        missingWest = true

    values.refAt(0)[] &= ~.West

    Swag.require(tookEast)
    Swag.require(tookSouth)
    Swag.require(missingWest)
    Swag.require(values.values[0] == .East)
}

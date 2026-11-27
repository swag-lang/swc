#global private

struct RuntimeSetSource
{
    value: s32
}

struct RuntimeSetTarget
{
    value:    s32
    tag:      s32
    calls:    s32
    sentinel: s32 = 1234
}

impl RuntimeSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        .value = value
        .tag   = 10
        .calls += 1
    }

    #[Swag.NoInline]
    mtd opSet(value: f32)
    {
        .value = cast(s32, value) * 2
        .tag   = 20
        .calls += 1
    }

    #[Swag.NoInline]
    mtd opSet(other: RuntimeSetSource)
    {
        .value = other.value + 5
        .tag   = 30
        .calls += 1
    }
}

struct RuntimeSetHolder
{
    target: RuntimeSetTarget
}

struct RuntimeParamSetTarget
{
    value:    s32
    tag:      s32
    sentinel: s32 = 777
}

enum RuntimeEnumSetSource: u32
{
    Red   = 0x11223344
    Green = 0x55667788
}

struct RuntimeEnumSetTarget
{
    raw:      u32
    tag:      s32
    sentinel: s32 = 4321
}

impl RuntimeParamSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        .value = value
        .tag   = 10
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd opSet(value: u16)
    {
        .value = cast(s32, value)
        .tag   = 20
    }

    #[Swag.NoInline]
    mtd opSet(value: u64)
    {
        .value    = cast(s32, value)
        .tag      = 30
        .sentinel = cast(s32, value)
    }
}

impl RuntimeEnumSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: u32)
    {
        .raw = value
        .tag = 10
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd opSet(value: RuntimeEnumSetSource)
    {
        .raw = cast(u32, value)
        .tag = 20
    }
}

struct RuntimeConstSetVector2
{
    x, y: f32
}

enum RuntimePaletteSource: u32
{
    Gray = 0xFF808080
    Blue = 0xFF3366CC
}

struct RuntimePaletteColor
{
    raw: u32
}

impl RuntimePaletteColor
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd opSet(value: RuntimePaletteSource)
    {
        .raw = cast(u32, value)
    }
}

struct RuntimePaletteCard
{
    label: string
    color: RuntimePaletteColor
}

impl RuntimeConstSetVector2
{
    #[Swag.ConstExpr]
    mtd opSet(one: f32)
    {
        .x, .y = one
    }
}

struct RuntimeLiteralSetTarget
{
    timeInSeconds: f32
    calls:         s32
    sentinel:      s32 = 1234
}

impl RuntimeLiteralSetTarget
{
    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        .calls += 1

        #static switch suffix
        {
        case "s":
            .timeInSeconds = value

        case "ms":
            .timeInSeconds = value / 1000.0

        case "min":
            .timeInSeconds = value * 60.0

        case "h":
            .timeInSeconds = value * 3600.0

        default:
            #error("invalid duration literal suffix '", suffix, "'")
        }
    }
}

struct RuntimeLiteralOverloadTarget
{
    timeInSeconds: f32
    tag:           s32
    calls:         s32
    sentinel:      s32 = 5678
}

impl RuntimeLiteralOverloadTarget
{
    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        .tag   = 10
        .calls += 1

        #static switch suffix
        {
        case "s":
            .timeInSeconds = value

        case "ms":
            .timeInSeconds = value / 1000.0

        case "min":
            .timeInSeconds = value * 60.0

        case "h":
            .timeInSeconds = value * 3600.0

        default:
            #error("invalid duration literal suffix '", suffix, "'")
        }
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        .tag   = 20
        .calls += 1

        #static switch suffix
        {
        case "s":
            .timeInSeconds = value

        case "ms":
            .timeInSeconds = value / 1000.0

        case "min":
            .timeInSeconds = value * 60.0

        case "h":
            .timeInSeconds = value * 3600.0

        default:
            #error("invalid duration literal suffix '", suffix, "'")
        }
    }
}

const RuntimeConstSetOne: RuntimeConstSetVector2 = 1.0
const RuntimePaletteCardOne = RuntimePaletteCard{"gray", RuntimePaletteSource.Gray}
const RuntimePaletteCards   = [
    RuntimePaletteCard{"gray", RuntimePaletteSource.Gray},
    RuntimePaletteCard{"blue", RuntimePaletteSource.Blue}
    ]
const RuntimePaletteColors: [2] RuntimePaletteColor = [RuntimePaletteSource.Gray, RuntimePaletteSource.Blue]
#assert(RuntimeConstSetOne.x == 1.0)
#assert(RuntimeConstSetOne.y == 1.0)
#assert(RuntimePaletteCardOne.color.raw == 0xFF808080_u32)
#assert(RuntimePaletteCards[1].color.raw == 0xFF3366CC_u32)
#assert(RuntimePaletteColors[0].raw == 0xFF808080_u32)

func assertRuntimeLiteralSet(value: RuntimeLiteralSetTarget, expectedSeconds: f32)
{
    Swag.assert(value.timeInSeconds == expectedSeconds)
    Swag.assert(value.calls == 1)
    Swag.assert(value.sentinel == 1234)
}

func assertRuntimeLiteralOverloadSet(value: RuntimeLiteralOverloadTarget, expectedSeconds: f32, expectedTag: s32)
{
    Swag.assert(value.timeInSeconds == expectedSeconds)
    Swag.assert(value.tag == expectedTag)
    Swag.assert(value.calls == 1)
    Swag.assert(value.sentinel == 5678)
}

#test
{
    var target = RuntimeSetTarget{}
    target = 42_s32

    #assert(#typeof(target) == RuntimeSetTarget)
    Swag.require(target.value == 42)
    Swag.require(target.tag == 10)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    var target = RuntimeSetTarget{}
    target = 3.5_f32

    Swag.require(target.value == 6)
    Swag.require(target.tag == 20)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    var source = RuntimeSetSource{value: 37}
    var target = RuntimeSetTarget{}
    target = source

    Swag.require(target.value == 42)
    Swag.require(target.tag == 30)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    let target: RuntimeSetTarget = 42_s32

    Swag.require(target.value == 42)
    Swag.require(target.tag == 10)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    let target: RuntimeSetTarget = 3.5_f32

    Swag.require(target.value == 6)
    Swag.require(target.tag == 20)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    var holder = RuntimeSetHolder{}
    holder.target = 77_s32

    Swag.require(holder.target.value == 77)
    Swag.require(holder.target.tag == 10)
    Swag.require(holder.target.calls == 1)
    Swag.require(holder.target.sentinel == 1234)
}

#test
{
    var target = RuntimeSetTarget{}
    let ptr    = &target
    ptr[] = 12_s32

    Swag.require(target.value == 12)
    Swag.require(target.tag == 10)
    Swag.require(target.calls == 1)
    Swag.require(target.sentinel == 1234)
}

#test
{
    let target: RuntimeParamSetTarget = 2_u64

    Swag.require(target.value == 2)
    Swag.require(target.tag == 30)
    Swag.require(target.sentinel == 2)
}

#test
{
    func takesExplicit(value: RuntimeParamSetTarget)
    {
        Swag.assert(value.value == 5)
        Swag.assert(value.tag == 10)
        Swag.assert(value.sentinel == 777)
    }

    func takesImplicit(value: RuntimeParamSetTarget)
    {
        Swag.assert(value.value == 7)
        Swag.assert(value.tag == 20)
        Swag.assert(value.sentinel == 777)
    }

    takesExplicit(cast(RuntimeParamSetTarget, 5_s32))
    takesImplicit(7_u16)
}

#test
{
    let initialized: RuntimeEnumSetTarget = RuntimeEnumSetSource.Red

    Swag.require(initialized.raw == 0x11223344)
    Swag.require(initialized.tag == 20)
    Swag.require(initialized.sentinel == 4321)

    func takesImplicit(value: RuntimeEnumSetTarget)
    {
        Swag.assert(value.raw == 0x55667788)
        Swag.assert(value.tag == 20)
        Swag.assert(value.sentinel == 4321)
    }

    takesImplicit(RuntimeEnumSetSource.Green)
}

#test
{
    let delay: RuntimeLiteralSetTarget = 5_s

    assertRuntimeLiteralSet(delay, 5.0)
}

#test
{
    let delay: RuntimeLiteralSetTarget = 500_ms

    assertRuntimeLiteralSet(delay, 0.5)
}

#test
{
    var delay = RuntimeLiteralSetTarget{}
    delay = 2_min

    assertRuntimeLiteralSet(delay, 120.0)
}

#test
{
    func takesImplicit(value: RuntimeLiteralSetTarget)
    {
        assertRuntimeLiteralSet(value, 0.5)
    }

    func takesExplicit(value: RuntimeLiteralSetTarget)
    {
        assertRuntimeLiteralSet(value, 3600.0)
    }

    takesImplicit(500_ms)
    takesExplicit(cast(RuntimeLiteralSetTarget, 1_h))
}

#test
{
    let delay: RuntimeLiteralOverloadTarget = 5_s

    assertRuntimeLiteralOverloadSet(delay, 5.0, 10)
}

#test
{
    let delay: RuntimeLiteralOverloadTarget = 1.5_s

    assertRuntimeLiteralOverloadSet(delay, 1.5, 20)
}

#test
{
    let intDelay = cast(RuntimeLiteralOverloadTarget, 250_ms)
    assertRuntimeLiteralOverloadSet(intDelay, 0.25, 10)

    let floatDelay = cast(RuntimeLiteralOverloadTarget, 0.5_h)
    assertRuntimeLiteralOverloadSet(floatDelay, 1800.0, 20)
}

#test
{
    func takesInt(value: RuntimeLiteralOverloadTarget)
    {
        assertRuntimeLiteralOverloadSet(value, 120.0, 10)
    }

    func takesFloat(value: RuntimeLiteralOverloadTarget)
    {
        assertRuntimeLiteralOverloadSet(value, 0.25, 20)
    }

    takesInt(2_min)
    takesFloat(250.0_ms)
}

#test
{
    Swag.require(RuntimeConstSetOne.x == 1.0)
    Swag.require(RuntimeConstSetOne.y == 1.0)
}

#test
{
    Swag.require(RuntimePaletteCardOne.label == "gray")
    Swag.require(RuntimePaletteCardOne.color.raw == 0xFF808080_u32)
    Swag.require(RuntimePaletteCards[0].color.raw == 0xFF808080_u32)
    Swag.require(RuntimePaletteCards[1].color.raw == 0xFF3366CC_u32)
    Swag.require(RuntimePaletteColors[0].raw == 0xFF808080_u32)
    Swag.require(RuntimePaletteColors[1].raw == 0xFF3366CC_u32)
}

#test
{
    var lhs = RuntimeSetTarget{value: 1, tag: 2, calls: 3}
    var rhs = RuntimeSetTarget{value: 9, tag: 11, calls: 13}
    lhs = rhs

    Swag.require(lhs.value == 9)
    Swag.require(lhs.tag == 11)
    Swag.require(lhs.calls == 13)
    Swag.require(lhs.sentinel == 1234)
}

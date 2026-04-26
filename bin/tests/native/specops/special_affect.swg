#global fileprivate

struct RuntimeSetSource
{
    value: s32
}

struct RuntimeSetTarget
{
    value: s32
    tag: s32
    calls: s32
    sentinel: s32 = 1234
}

impl RuntimeSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        .value = value
        .tag = 10
        .calls += 1
    }

    #[Swag.NoInline]
    mtd opSet(value: f32)
    {
        .value = cast(s32) value * 2
        .tag = 20
        .calls += 1
    }

    #[Swag.NoInline]
    mtd opSet(other: RuntimeSetSource)
    {
        .value = other.value + 5
        .tag = 30
        .calls += 1
    }
}

struct RuntimeSetHolder
{
    target: RuntimeSetTarget
}

struct RuntimeParamSetTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 777
}

impl RuntimeParamSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        .value = value
        .tag = 10
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd opSet(value: u16)
    {
        .value = cast(s32) value
        .tag = 20
    }

    #[Swag.Complete, Swag.NoInline]
    mtd opSet(value: u64)
    {
        .value = cast(s32) value
        .tag = 30
        .sentinel = cast(s32) value
    }
}

struct RuntimeConstSetVector2
{
    x, y: f32
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
    calls: s32
    sentinel: s32 = 1234
}

impl RuntimeLiteralSetTarget
{
    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        .calls += 1

        #if suffix == "s" do
            .timeInSeconds = value
        #elif suffix == "ms" do
            .timeInSeconds = value / 1000.0
        #elif suffix == "min" do
            .timeInSeconds = value * 60.0
        #elif suffix == "h" do
            .timeInSeconds = value * 3600.0
        #else do
            #error("invalid duration literal suffix '" ++ suffix ++ "'")
    }
}

struct RuntimeLiteralOverloadTarget
{
    timeInSeconds: f32
    tag: s32
    calls: s32
    sentinel: s32 = 5678
}

impl RuntimeLiteralOverloadTarget
{
    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        .tag = 10
        .calls += 1

        #if suffix == "s" do
            .timeInSeconds = value
        #elif suffix == "ms" do
            .timeInSeconds = value / 1000.0
        #elif suffix == "min" do
            .timeInSeconds = value * 60.0
        #elif suffix == "h" do
            .timeInSeconds = value * 3600.0
        #else do
            #error("invalid duration literal suffix '" ++ suffix ++ "'")
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        .tag = 20
        .calls += 1

        #if suffix == "s" do
            .timeInSeconds = value
        #elif suffix == "ms" do
            .timeInSeconds = value / 1000.0
        #elif suffix == "min" do
            .timeInSeconds = value * 60.0
        #elif suffix == "h" do
            .timeInSeconds = value * 3600.0
        #else do
            #error("invalid duration literal suffix '" ++ suffix ++ "'")
    }
}

const RuntimeConstSetOne: RuntimeConstSetVector2 = 1.0
#assert(RuntimeConstSetOne.x == 1.0)
#assert(RuntimeConstSetOne.y == 1.0)

func assertRuntimeLiteralSet(value: RuntimeLiteralSetTarget, expectedSeconds: f32)
{
    @assert(value.timeInSeconds == expectedSeconds)
    @assert(value.calls == 1)
    @assert(value.sentinel == 1234)
}

func assertRuntimeLiteralOverloadSet(value: RuntimeLiteralOverloadTarget, expectedSeconds: f32, expectedTag: s32)
{
    @assert(value.timeInSeconds == expectedSeconds)
    @assert(value.tag == expectedTag)
    @assert(value.calls == 1)
    @assert(value.sentinel == 5678)
}

#test
{
    var target = RuntimeSetTarget{}
    target = 42's32

    #assert(#typeof(target) == RuntimeSetTarget)
    @assert(target.value == 42)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var target = RuntimeSetTarget{}
    target = 3.5'f32

    @assert(target.value == 6)
    @assert(target.tag == 20)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var source = RuntimeSetSource{value: 37}
    var target = RuntimeSetTarget{}
    target = source

    @assert(target.value == 42)
    @assert(target.tag == 30)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeSetTarget = 42's32

    @assert(target.value == 42)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeSetTarget = 3.5'f32

    @assert(target.value == 6)
    @assert(target.tag == 20)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var holder = RuntimeSetHolder{}
    holder.target = 77's32

    @assert(holder.target.value == 77)
    @assert(holder.target.tag == 10)
    @assert(holder.target.calls == 1)
    @assert(holder.target.sentinel == 1234)
}

#test
{
    var target = RuntimeSetTarget{}
    let ptr = &target
    dref ptr = 12's32

    @assert(target.value == 12)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeParamSetTarget = 2'u64

    @assert(target.value == 2)
    @assert(target.tag == 30)
    @assert(target.sentinel == 2)
}

#test
{
    func takesExplicit(value: RuntimeParamSetTarget)
    {
        @assert(value.value == 5)
        @assert(value.tag == 10)
        @assert(value.sentinel == 777)
    }

    func takesImplicit(value: RuntimeParamSetTarget)
    {
        @assert(value.value == 7)
        @assert(value.tag == 20)
        @assert(value.sentinel == 777)
    }

    takesExplicit(cast(RuntimeParamSetTarget) 5's32)
    takesImplicit(7'u16)
}

#test
{
    let delay: RuntimeLiteralSetTarget = 5's

    assertRuntimeLiteralSet(delay, 5.0)
}

#test
{
    let delay: RuntimeLiteralSetTarget = 500'ms

    assertRuntimeLiteralSet(delay, 0.5)
}

#test
{
    var delay = RuntimeLiteralSetTarget{}
    delay = 2'min

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

    takesImplicit(500'ms)
    takesExplicit(cast(RuntimeLiteralSetTarget) 1'h)
}

#test
{
    let delay: RuntimeLiteralOverloadTarget = 5's

    assertRuntimeLiteralOverloadSet(delay, 5.0, 10)
}

#test
{
    let delay: RuntimeLiteralOverloadTarget = 1.5's

    assertRuntimeLiteralOverloadSet(delay, 1.5, 20)
}

#test
{
    let intDelay = cast(RuntimeLiteralOverloadTarget) 250'ms
    assertRuntimeLiteralOverloadSet(intDelay, 0.25, 10)

    let floatDelay = cast(RuntimeLiteralOverloadTarget) 0.5'h
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

    takesInt(2'min)
    takesFloat(250.0'ms)
}

#test
{
    @assert(RuntimeConstSetOne.x == 1.0)
    @assert(RuntimeConstSetOne.y == 1.0)
}

#test
{
    var lhs = RuntimeSetTarget{value: 1, tag: 2, calls: 3}
    var rhs = RuntimeSetTarget{value: 9, tag: 11, calls: 13}
    lhs = rhs

    @assert(lhs.value == 9)
    @assert(lhs.tag == 11)
    @assert(lhs.calls == 13)
    @assert(lhs.sentinel == 1234)
}

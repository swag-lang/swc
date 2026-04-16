#global fileprivate

struct RuntimeAffectSource
{
    value: s32
}

struct RuntimeAffectTarget
{
    value: s32
    tag: s32
    calls: s32
    sentinel: s32 = 1234
}

impl RuntimeAffectTarget
{
    #[Swag.Overload, Swag.NoInline]
    mtd opAffect(value: s32)
    {
        .value = value
        .tag = 10
        .calls += 1
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opAffect(value: f32)
    {
        .value = cast(s32) value * 2
        .tag = 20
        .calls += 1
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opAffect(other: RuntimeAffectSource)
    {
        .value = other.value + 5
        .tag = 30
        .calls += 1
    }
}

struct RuntimeAffectHolder
{
    target: RuntimeAffectTarget
}

struct RuntimeParamAffectTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 777
}

impl RuntimeParamAffectTarget
{
    #[Swag.Overload, Swag.NoInline]
    mtd opAffect(value: s32)
    {
        .value = value
        .tag = 10
    }

    #[Swag.Implicit, Swag.Overload, Swag.NoInline]
    mtd opAffect(value: u16)
    {
        .value = cast(s32) value
        .tag = 20
    }

    #[Swag.Complete, Swag.Overload, Swag.NoInline]
    mtd opAffect(value: u64)
    {
        .value = cast(s32) value
        .tag = 30
        .sentinel = cast(s32) value
    }
}

struct RuntimeConstAffectVector2
{
    x, y: f32
}

impl RuntimeConstAffectVector2
{
    #[Swag.ConstExpr]
    mtd opAffect(one: f32)
    {
        .x, .y = one
    }
}

struct RuntimeLiteralAffectTarget
{
    timeInSeconds: f32
    calls: s32
    sentinel: s32 = 1234
}

impl RuntimeLiteralAffectTarget
{
    #[Swag.Implicit, Swag.NoInline]
    mtd(suffix: string) opAffectLiteral(value: s32)
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

const RuntimeConstAffectOne: RuntimeConstAffectVector2 = 1.0
#assert(RuntimeConstAffectOne.x == 1.0)
#assert(RuntimeConstAffectOne.y == 1.0)

#test
{
    var target = RuntimeAffectTarget{}
    target = 42's32

    #assert(#typeof(target) == RuntimeAffectTarget)
    @assert(target.value == 42)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var target = RuntimeAffectTarget{}
    target = 3.5'f32

    @assert(target.value == 6)
    @assert(target.tag == 20)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var source = RuntimeAffectSource{value: 37}
    var target = RuntimeAffectTarget{}
    target = source

    @assert(target.value == 42)
    @assert(target.tag == 30)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeAffectTarget = 42's32

    @assert(target.value == 42)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeAffectTarget = 3.5'f32

    @assert(target.value == 6)
    @assert(target.tag == 20)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    var holder = RuntimeAffectHolder{}
    holder.target = 77's32

    @assert(holder.target.value == 77)
    @assert(holder.target.tag == 10)
    @assert(holder.target.calls == 1)
    @assert(holder.target.sentinel == 1234)
}

#test
{
    var target = RuntimeAffectTarget{}
    let ptr = &target
    dref ptr = 12's32

    @assert(target.value == 12)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
    @assert(target.sentinel == 1234)
}

#test
{
    let target: RuntimeParamAffectTarget = 2'u64

    @assert(target.value == 2)
    @assert(target.tag == 30)
    @assert(target.sentinel == 2)
}

#test
{
    func takesExplicit(value: RuntimeParamAffectTarget)
    {
        @assert(value.value == 5)
        @assert(value.tag == 10)
        @assert(value.sentinel == 777)
    }

    func takesImplicit(value: RuntimeParamAffectTarget)
    {
        @assert(value.value == 7)
        @assert(value.tag == 20)
        @assert(value.sentinel == 777)
    }

    takesExplicit(cast(RuntimeParamAffectTarget) 5's32)
    takesImplicit(7'u16)
}

#test
{
    let delay: RuntimeLiteralAffectTarget = 5's

    @assert(delay.timeInSeconds == 5.0)
    @assert(delay.calls == 1)
    @assert(delay.sentinel == 1234)
}

#test
{
    let delay: RuntimeLiteralAffectTarget = 500'ms

    @assert(delay.timeInSeconds == 0.5)
    @assert(delay.calls == 1)
    @assert(delay.sentinel == 1234)
}

#test
{
    var delay = RuntimeLiteralAffectTarget{}
    delay = 2'min

    @assert(delay.timeInSeconds == 120.0)
    @assert(delay.calls == 1)
    @assert(delay.sentinel == 1234)
}

#test
{
    func takesImplicit(value: RuntimeLiteralAffectTarget)
    {
        @assert(value.timeInSeconds == 0.5)
        @assert(value.calls == 1)
        @assert(value.sentinel == 1234)
    }

    func takesExplicit(value: RuntimeLiteralAffectTarget)
    {
        @assert(value.timeInSeconds == 3600.0)
        @assert(value.calls == 1)
        @assert(value.sentinel == 1234)
    }

    takesImplicit(500'ms)
    takesExplicit(cast(RuntimeLiteralAffectTarget) 1'h)
}

#test
{
    @assert(RuntimeConstAffectOne.x == 1.0)
    @assert(RuntimeConstAffectOne.y == 1.0)
}

#test
{
    var lhs = RuntimeAffectTarget{value: 1, tag: 2, calls: 3}
    var rhs = RuntimeAffectTarget{value: 9, tag: 11, calls: 13}
    lhs = rhs

    @assert(lhs.value == 9)
    @assert(lhs.tag == 11)
    @assert(lhs.calls == 13)
    @assert(lhs.sentinel == 1234)
}

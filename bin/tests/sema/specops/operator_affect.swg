#global fileprivate

struct SetSource
{
    value: s32
}

struct SetTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 1234
}

impl SetTarget
{
    mtd opSet(value: s32)
    {
        .value = value
        .tag = 10
    }

    mtd opSet(value: f32)
    {
        .value = cast(s32) value
        .tag = 20
    }

    mtd opSet(other: SetSource)
    {
        .value = other.value + 1
        .tag = 30
    }
}

struct SetHolder
{
    target: SetTarget
}

struct ParamSetTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 777
}

impl ParamSetTarget
{
    mtd opSet(value: s32)
    {
        .value = value
        .tag = 10
    }

    #[Swag.Implicit]
    mtd opSet(value: u16)
    {
        .value = cast(s32) value
        .tag = 20
    }

    #[Swag.Complete]
    mtd opSet(value: u64)
    {
        .value = cast(s32) value
        .tag = 30
        .sentinel = cast(s32) value
    }
}

struct ConstSetVector2
{
    x, y: f32
}

impl ConstSetVector2
{
    #[Swag.ConstExpr]
    mtd opSet(one: f32)
    {
        .x, .y = one
    }
}

struct LiteralSetTarget
{
    timeInSeconds: f32
}

impl LiteralSetTarget
{
    #[Swag.Implicit]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
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

struct LiteralOverloadTarget
{
    timeInSeconds: f32
    tag: s32
}

impl LiteralOverloadTarget
{
    #[Swag.Implicit]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        .tag = 10

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

    #[Swag.Implicit]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        .tag = 20

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

const ConstSetOne: ConstSetVector2 = 1.0
#assert(ConstSetOne.x == 1.0)
#assert(ConstSetOne.y == 1.0)

#test
{
    var target = SetTarget{}
    target = 42's32
    target = 3.5'f32
    let source = SetSource{value: 8}
    target = source

    #assert(#typeof(target) == SetTarget)
}

#test
{
    let fromInt: SetTarget = 42's32
    var fromFloat: SetTarget = 3.5'f32

    #assert(#typeof(fromInt) == SetTarget)
    #assert(#typeof(fromFloat) == SetTarget)
}

#test
{
    var lhs = SetTarget{value: 1, tag: 2}
    var rhs = SetTarget{value: 9, tag: 11}
    lhs = rhs

    #assert(#typeof(lhs) == SetTarget)
}

#test
{
    var holder = SetHolder{}
    holder.target = 77's32
}

#test
{
    var target = SetTarget{}
    let ptr = &target
    dref ptr = 99's32
}

#test
{
    func takesExplicit(value: ParamSetTarget) {}
    func takesImplicit(value: ParamSetTarget) {}

    takesExplicit(cast(ParamSetTarget) 5's32)
    takesImplicit(7'u16)

    let complete: ParamSetTarget = 2'u64
    #assert(#typeof(complete) == ParamSetTarget)
}

#test
{
    let delay1: LiteralSetTarget = 5's
    let delay2: LiteralSetTarget = 500'ms
    let delay3 = cast(LiteralSetTarget) 2'min
    var delay4 = LiteralSetTarget{}
    delay4 = 1'h

    func takesImplicit(value: LiteralSetTarget) {}
    takesImplicit(5'ms)

    #assert(#typeof(delay1) == LiteralSetTarget)
    #assert(#typeof(delay2) == LiteralSetTarget)
    #assert(#typeof(delay3) == LiteralSetTarget)
    #assert(#typeof(delay4) == LiteralSetTarget)
}

#test
{
    let fromInt: LiteralOverloadTarget = 5's
    let fromFloat: LiteralOverloadTarget = 1.5's

    let castInt = cast(LiteralOverloadTarget) 250'ms
    let castFloat = cast(LiteralOverloadTarget) 0.5'h

    func takesImplicit(value: LiteralOverloadTarget) {}
    takesImplicit(2'min)
    takesImplicit(250.0'ms)

    #assert(#typeof(fromInt) == LiteralOverloadTarget)
    #assert(#typeof(fromFloat) == LiteralOverloadTarget)
    #assert(#typeof(castInt) == LiteralOverloadTarget)
    #assert(#typeof(castFloat) == LiteralOverloadTarget)
}

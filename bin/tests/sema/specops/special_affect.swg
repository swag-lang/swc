#global fileprivate

struct AffectSource
{
    value: s32
}

struct AffectTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 1234
}

impl AffectTarget
{
    #[Swag.Overload]
    mtd opAffect(value: s32)
    {
        .value = value
        .tag = 10
    }

    #[Swag.Overload]
    mtd opAffect(value: f32)
    {
        .value = cast(s32) value
        .tag = 20
    }

    #[Swag.Overload]
    mtd opAffect(other: AffectSource)
    {
        .value = other.value + 1
        .tag = 30
    }
}

struct AffectHolder
{
    target: AffectTarget
}

struct ParamAffectTarget
{
    value: s32
    tag: s32
    sentinel: s32 = 777
}

impl ParamAffectTarget
{
    #[Swag.Overload]
    mtd opAffect(value: s32)
    {
        .value = value
        .tag = 10
    }

    #[Swag.Implicit, Swag.Overload]
    mtd opAffect(value: u16)
    {
        .value = cast(s32) value
        .tag = 20
    }

    #[Swag.Complete, Swag.Overload]
    mtd opAffect(value: u64)
    {
        .value = cast(s32) value
        .tag = 30
        .sentinel = cast(s32) value
    }
}

struct ConstAffectVector2
{
    x, y: f32
}

impl ConstAffectVector2
{
    #[Swag.ConstExpr]
    mtd opAffect(one: f32)
    {
        .x, .y = one
    }
}

struct LiteralAffectTarget
{
    timeInSeconds: f32
}

impl LiteralAffectTarget
{
    #[Swag.Implicit]
    mtd(suffix: string) opAffectLiteral(value: s32)
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
    #[Swag.Implicit, Swag.Overload]
    mtd(suffix: string) opAffectLiteral(value: s32)
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

    #[Swag.Implicit, Swag.Overload]
    mtd(suffix: string) opAffectLiteral(value: f32)
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

const ConstAffectOne: ConstAffectVector2 = 1.0
#assert(ConstAffectOne.x == 1.0)
#assert(ConstAffectOne.y == 1.0)

#test
{
    var target = AffectTarget{}
    target = 42's32
    target = 3.5'f32
    let source = AffectSource{value: 8}
    target = source

    #assert(#typeof(target) == AffectTarget)
}

#test
{
    let fromInt: AffectTarget = 42's32
    var fromFloat: AffectTarget = 3.5'f32

    #assert(#typeof(fromInt) == AffectTarget)
    #assert(#typeof(fromFloat) == AffectTarget)
}

#test
{
    var lhs = AffectTarget{value: 1, tag: 2}
    var rhs = AffectTarget{value: 9, tag: 11}
    lhs = rhs

    #assert(#typeof(lhs) == AffectTarget)
}

#test
{
    var holder = AffectHolder{}
    holder.target = 77's32
}

#test
{
    var target = AffectTarget{}
    let ptr = &target
    dref ptr = 99's32
}

#test
{
    func takesExplicit(value: ParamAffectTarget) {}
    func takesImplicit(value: ParamAffectTarget) {}

    takesExplicit(cast(ParamAffectTarget) 5's32)
    takesImplicit(7'u16)

    let complete: ParamAffectTarget = 2'u64
    #assert(#typeof(complete) == ParamAffectTarget)
}

#test
{
    let delay1: LiteralAffectTarget = 5's
    let delay2: LiteralAffectTarget = 500'ms
    let delay3 = cast(LiteralAffectTarget) 2'min
    var delay4 = LiteralAffectTarget{}
    delay4 = 1'h

    func takesImplicit(value: LiteralAffectTarget) {}
    takesImplicit(5'ms)

    #assert(#typeof(delay1) == LiteralAffectTarget)
    #assert(#typeof(delay2) == LiteralAffectTarget)
    #assert(#typeof(delay3) == LiteralAffectTarget)
    #assert(#typeof(delay4) == LiteralAffectTarget)
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

#test
{
    const target = AffectTarget{}
    target = 1 // swc-expected-error {{sema_err_assign_to_const}}
}

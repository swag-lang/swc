#global fileprivate

struct AffectSource
{
    value: s32
}

struct AffectTarget
{
    value: s32
    tag: s32
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
    const target = AffectTarget{}
    target = 1 // swc-expected-error {{sema_err_assign_to_const}}
}

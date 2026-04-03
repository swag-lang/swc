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

#test
{
    var target = RuntimeAffectTarget{}
    target = 42's32

    #assert(#typeof(target) == RuntimeAffectTarget)
    @assert(target.value == 42)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
}

#test
{
    var target = RuntimeAffectTarget{}
    target = 3.5'f32

    @assert(target.value == 6)
    @assert(target.tag == 20)
    @assert(target.calls == 1)
}

#test
{
    var source = RuntimeAffectSource{value: 37}
    var target = RuntimeAffectTarget{}
    target = source

    @assert(target.value == 42)
    @assert(target.tag == 30)
    @assert(target.calls == 1)
}

#test
{
    var holder = RuntimeAffectHolder{}
    holder.target = 77's32

    @assert(holder.target.value == 77)
    @assert(holder.target.tag == 10)
    @assert(holder.target.calls == 1)
}

#test
{
    var target = RuntimeAffectTarget{}
    let ptr = &target
    dref ptr = 12's32

    @assert(target.value == 12)
    @assert(target.tag == 10)
    @assert(target.calls == 1)
}

#test
{
    var lhs = RuntimeAffectTarget{value: 1, tag: 2, calls: 3}
    var rhs = RuntimeAffectTarget{value: 9, tag: 11, calls: 13}
    lhs = rhs

    @assert(lhs.value == 9)
    @assert(lhs.tag == 11)
    @assert(lhs.calls == 13)
}

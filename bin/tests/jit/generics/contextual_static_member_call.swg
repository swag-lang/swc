#global fileprivate

struct(T) ContextStaticVec2
{
    x: T
    y: T
}

impl ContextStaticVec2
{
    func make(x: T, y: T)->ContextStaticVec2
    {
        return {x: x, y: y}
    }

    func doubled(const me)->ContextStaticVec2
    {
        return ContextStaticVec2.make(me.x + me.x, me.y + me.y)
    }
}

alias ContextStaticAlias = ContextStaticVec2

struct(T) ContextStaticBox
{
    value: ContextStaticVec2'T
}

impl ContextStaticBox
{
    func expanded(const me)->ContextStaticVec2
    {
        return ContextStaticVec2.make(me.value.x + 1, me.value.y + 1)
    }

    func expandedViaAlias(const me)->ContextStaticVec2
    {
        return ContextStaticAlias.make(me.value.x + 2, me.value.y + 2)
    }
}

#test
{
    var v: ContextStaticVec2's32 = {x: 3, y: 4}
    let doubled = v.doubled()

    #assert(#typeof(doubled) == ContextStaticVec2's32)
    @assert(doubled.x == 6)
    @assert(doubled.y == 8)
}

#test
{
    var box: ContextStaticBox's32 = {value: {x: 10, y: 20}}
    let expanded = box.expanded()
    let aliased = box.expandedViaAlias()

    #assert(#typeof(expanded) == ContextStaticVec2's32)
    #assert(#typeof(aliased) == ContextStaticVec2's32)
    @assert(expanded.x == 11)
    @assert(expanded.y == 21)
    @assert(aliased.x == 12)
    @assert(aliased.y == 22)
}

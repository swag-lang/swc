#global fileprivate

struct ShadowItem
{
    count: s32
}

struct SetterItem
{
    count: s32
}

impl SetterItem
{
    mtd opSet(value: s32)
    {
        .count = value
    }
}

struct(T) GenericSetterItem
{
    count: u64
}

impl GenericSetterItem
{
    mtd opSet(values: const [..] T)
    {
        me.count = @countof(values)
    }
}

func set()->ShadowItem { return {count: -1} }
func set(value: s32)->s32 { return value }
func(T) set(value: T)->T { return value }
func makeShadowItem(value: s32)->ShadowItem { return {count: value} }

#test
{
    let set: ShadowItem = {count: 3}
    @assert(set.count == 3)
}

#test
{
    let set: ShadowItem = makeShadowItem(4)
    @assert(set.count == 4)
}

func readShadow(set: ShadowItem)->s32
{
    return set.count
}

#test
{
    @assert(readShadow({count: 5}) == 5)
}

#test
{
    {
        let set: ShadowItem = {count: 6}
        @assert(set.count == 6)
    }
}

#test
{
    let set: ShadowItem = makeShadowItem(7)
    @assert(set.count == 7)
}

#test
{
    let set: SetterItem = 8
    @assert(set.count == 8)
}

#test
{
    let values = [1, 2, 3]
    let set: GenericSetterItem's32 = values[to]
    @assert(set.count == 3)
}

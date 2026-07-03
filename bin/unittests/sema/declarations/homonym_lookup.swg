#global private

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

func semaTest001()
{
    let set: ShadowItem = {count: 3}
    let count = set.count

    #assert(#typeof(count) == s32)
}

func semaTest002()
{
    let set: ShadowItem = makeShadowItem(4)
    let count = set.count

    #assert(#typeof(count) == s32)
}

func readShadow(set: ShadowItem)->s32
{
    return set.count
}

func semaTest003()
{
    let count = readShadow({count: 5})
    #assert(#typeof(count) == s32)
}

func semaTest004()
{
    {
        let set: ShadowItem = {count: 6}
        let count = set.count
        #assert(#typeof(count) == s32)
    }
}

func semaTest005()
{
    let set: ShadowItem = makeShadowItem(7)
    let count = set.count

    #assert(#typeof(count) == s32)
}

func semaTest006()
{
    let set: SetterItem = 8
    let count = set.count

    #assert(#typeof(count) == s32)
}

func semaTest007()
{
    let values = [1, 2, 3]
    let set: GenericSetterItem's32 = values[to]
    let count = set.count

    #assert(#typeof(count) == u64)
}

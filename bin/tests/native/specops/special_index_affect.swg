#global fileprivate

struct RuntimeIndexBox
{
    first:  s32
    second: s32
    reads:  s32
    writes: s32
}

impl RuntimeIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> s32
    {
        .reads += 1
        if index == 0 do
            return .first
        return .second
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opIndexSet(index: s32, value: s32)
    {
        .writes += 1
        if index == 0 do
            .first = value
        else do
            .second = value
    }
}

struct RuntimeWriteOnlyIndexBox
{
    first:  s32
    second: s32
    writes: s32
}

impl RuntimeWriteOnlyIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndexSet(index: s32, value: s32)
    {
        .writes += 1
        if index == 0 do
            .first = value
        else do
            .second = value
    }
}

struct RuntimeRefIndexBox
{
    values: [2] s32
    reads:  s32
    writes: s32
}

impl RuntimeRefIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> &s32
    {
        .reads += 1
        return &.values[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opIndexSet(index: s32, value: s32)
    {
        .writes += 1
        .values[index] = value
    }
}

struct RuntimeIndexHolder
{
    value:     RuntimeIndexBox
    writeOnly: RuntimeWriteOnlyIndexBox
}

#test
{
    var box = RuntimeIndexBox{}
    box[0] = 42

    @assert(box.first == 42)
    @assert(box.second == 0)
    @assert(box.writes == 1)
    @assert(box.reads == 0)

    let observed = box[0]
    @assert(observed == 42)
    @assert(box.reads == 1)
    @assert(box.writes == 1)
}

#test
{
    var holder = RuntimeIndexHolder{}
    holder.value[1] = 19
    holder.writeOnly[0] = 5

    @assert(holder.value.first == 0)
    @assert(holder.value.second == 19)
    @assert(holder.value.writes == 1)
    @assert(holder.value.reads == 0)

    @assert(holder.writeOnly.first == 5)
    @assert(holder.writeOnly.second == 0)
    @assert(holder.writeOnly.writes == 1)
}

#test
{
    var box = RuntimeRefIndexBox{}
    box[0] = 32

    @assert(box.values[0] == 32)
    @assert(box.values[1] == 0)
    @assert(box.writes == 1)
    @assert(box.reads == 0)

    let observed = box[0]
    @assert(observed == 32)
    @assert(box.reads == 1)
}

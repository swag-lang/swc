#global fileprivate

struct WriteOnlyIndexBox
{
    first:  s32
    second: s32
}

impl WriteOnlyIndexBox
{
    mtd opIndexSet(index: s32, value: s32)
    {
        if index == 0 do
            .first = value
        else do
            .second = value
    }
}

struct WriteOnlyIndexHolder
{
    value: WriteOnlyIndexBox
}

struct RefAndSetIndexBox
{
    values: [2] s32
}

impl RefAndSetIndexBox
{
    mtd opIndex(index: s32) -> &s32
    {
        return &.values[index]
    }

    mtd opIndexSet(index: s32, value: s32)
    {
        .values[index] = value
    }
}

#test
{
    var box = WriteOnlyIndexBox{}
    box[0] = 7

    var holder = WriteOnlyIndexHolder{}
    holder.value[0] = 3

    #assert(#typeof(box) == WriteOnlyIndexBox)
}

#test
{
    var box = RefAndSetIndexBox{}
    box[0] = 11

    #assert(#typeof(box) == RefAndSetIndexBox)
}

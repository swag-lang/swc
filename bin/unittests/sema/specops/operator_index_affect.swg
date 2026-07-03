#global private

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

struct ConstReadAndSetIndexBox
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

impl ConstReadAndSetIndexBox
{
    mtd const opIndex(index: s32) -> s32
    {
        return .values[index]
    }

    mtd opIndexSet(index: s32, value: s32)
    {
        .values[index] = value
    }
}

func semaTest001()
{
    var box = WriteOnlyIndexBox{}
    box[0] = 7

    var holder = WriteOnlyIndexHolder{}
    holder.value[0] = 3

    #assert(#typeof(box) == WriteOnlyIndexBox)
}

func semaTest002()
{
    var box = RefAndSetIndexBox{}
    box[0] = 11

    #assert(#typeof(box) == RefAndSetIndexBox)
}

func semaTest003()
{
    var box = ConstReadAndSetIndexBox{}
    box[0] = 17

    #assert(#typeof(box) == ConstReadAndSetIndexBox)
}

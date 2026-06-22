#global fileprivate

struct InlineRefIndexWriteValues
{
    values: [2] s32
}

struct InlineRefIndexWriteInfo
{
    stored: s32
    index: s32
}

impl InlineRefIndexWriteValues
{
    mtd const opIndex(index: u64)->const &s32
    {
        return &.values[index]
    }

    mtd opIndex(index: u64)->&s32
    {
        return &.values[index]
    }
}

#[Swag.Inline]
func inlineRefIndexWriteAt(values: &InlineRefIndexWriteValues, index: &s32, value: s32)
{
    values[index] = value
    index += 1
}

func inlineRefIndexWriteResult()->InlineRefIndexWriteInfo
{
    var values = InlineRefIndexWriteValues{values: [11, 22]}
    var index = 0
    inlineRefIndexWriteAt(&values, &index, 42)
    return {values[0], index}
}

func semaTest001()
{
    const V = #run inlineRefIndexWriteResult()
    #assert(V.stored == 42)
    #assert(V.index == 1)
}

#global private

struct InlineRefIndexBox
{
    buffer: [2] s32
}

impl InlineRefIndexBox
{
    #[Swag.Inline]
    mtd opIndex(index: s32)->&s32
    {
        return &.buffer[index]
    }
}

func semaTest001()
{
    var box = InlineRefIndexBox{buffer: [3, 5]}
    let value = box[1]

    #assert(#typeof(value) == s32)
}

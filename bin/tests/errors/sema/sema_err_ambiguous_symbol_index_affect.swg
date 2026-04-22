#global fileprivate

struct AmbiguousIndexWrite
{
    data: [1] s32
}

impl AmbiguousIndexWrite
{
    mtd opIndex(index: s32) -> &s32
    {
        return &.data[index]
    }

    mtd opIndexSet(index: s32, value: s32)
    {
        .data[index] = value
    }
}

#test
{
    var box = AmbiguousIndexWrite{}
    box[0] = 42 // swc-expected-error {{sema_err_ambiguous_symbol}}
}

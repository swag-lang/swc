#global fileprivate

struct(T) GenericSizeEntry
{
    hash:   u32
    first:  T
    second: s32
}

struct(T) GenericSizeBox
{
    entries: [*] GenericSizeEntry
}

impl GenericSizeBox
{
    #[Swag.NoInline]
    mtd byteCount(count: u64)->u64
    {
        #assert(#sizeof(GenericSizeEntry) == #sizeof(GenericSizeEntry's32))
        return count * #sizeof(GenericSizeEntry)
    }
}

#test
{
    var box: GenericSizeBox's32
    @assert(box.byteCount(4) == 48)
}

#global fileprivate

var InlineContextualTypeSize: u64

func(T) recordInlineContextualType(value: T)
{
    InlineContextualTypeSize += #sizeof(T)
}

#[Swag.Inline]
func forwardInlineByte(value: u8)
{
    recordInlineContextualType(value)
}

#test
{
    InlineContextualTypeSize = 0
    forwardInlineByte(0)
    @assert(InlineContextualTypeSize == 1)
}

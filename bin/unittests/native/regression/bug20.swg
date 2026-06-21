#global fileprivate

struct InlineMethodClosureReceiver
{
    base: s32
}

impl InlineMethodClosureReceiver
{
    #[Swag.Inline]
    mtd makeInlineMethodClosure(offset: s32)->func||(&InlineMethodClosureReceiver, s32)->s32
    {
        return mtd|offset|(value: s32)->s32
        {
            return .base + offset + value
        }
    }
}

#test
{
    var receiver = InlineMethodClosureReceiver{base: 7}
    let cb = receiver.makeInlineMethodClosure(3)
    @assert(cb(&receiver, 5) == 15)
}

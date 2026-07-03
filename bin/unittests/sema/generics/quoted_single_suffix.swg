#global private

struct(T) QuotedSingleSuffixBox
{
    value: T
}

func semaTest001()
{
    let box: QuotedSingleSuffixBox'{ x, y: s32 } = {value: {x: 1, y: 2}}
    #assert(#typeof(box.value.x) == s32)
    #assert(#typeof(box.value.y) == s32)
}

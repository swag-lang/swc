#global fileprivate

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

struct(T) Wrapper
{
    item: Box'T
}

struct(T, N: s32) DoubleBuffer
{
    first: Buffer'(T, N)
    second: Buffer'(T, N)
}

struct(T, N: s32 = 2) DefaultBuffer
{
    values: [N] T
}

#test
{
    let box: Box'bool
    let buffer: Buffer'(s32, 3)
    let wrapped: Wrapper'string
    let doubled: DoubleBuffer'(u8, 4)
    let partial: DefaultBuffer'u16

    #assert(#typeof(box.value) == bool)
    #assert(#typeof(buffer.values) == #type [3] s32)
    #assert(#typeof(wrapped.item.value) == string)
    #assert(#typeof(doubled.first.values) == #type [4] u8)
    #assert(#typeof(doubled.second.values) == #type [4] u8)
    #assert(#typeof(partial.values) == #type [2] u16)
}

#test
{
    {
        struct(T) LocalBox
        {
            value: T
        }

        let intBox: LocalBox's32
        let boolBox: LocalBox'bool

        #assert(#typeof(intBox.value) == s32)
        #assert(#typeof(boolBox.value) == bool)
    }
    {
        struct(T, N: s32) LocalBuffer
        {
            values: [N] T
        }

        let buffer: LocalBuffer'(u16, 3)
        #assert(#typeof(buffer.values) == #type [3] u16)
    }
}

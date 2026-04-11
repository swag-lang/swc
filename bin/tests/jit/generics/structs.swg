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

func(T, N: s32) bufferCount(buffer: Buffer'(T, N))->s32 => N

func sumFour(buffer: Buffer'(s32, 4))->s32
{
    return buffer.values[0] + buffer.values[1] + buffer.values[2] + buffer.values[3]
}

#test
{
    let stringBox: Box'string = {value: "swag"}
    let wrapped: Wrapper'string = {item: stringBox}
    let buffer: Buffer'(s32, 4) = {values: [1, 2, 3, 4]}
    let first: Buffer'(u8, 3) = {values: [1'u8, 2, 3]}
    let second: Buffer'(u8, 3) = {values: [4'u8, 5, 6]}
    let doubled: DoubleBuffer'(u8, 3) = {first: first, second: second}
    let partial: DefaultBuffer'u16 = {values: [10'u16, 20]}

    #assert(#typeof(wrapped.item.value) == string)
    #assert(#typeof(partial.values) == #type [2] u16)

    @assert(bufferCount'(s32, 4)(buffer) == 4)
    @assert(sumFour(buffer) == 10)
    @assert(wrapped.item.value == "swag")
    @assert(doubled.second.values[2] == 6'u8)
    @assert(partial.values[0] == 10'u16)
    @assert(partial.values[1] == 20'u16)
}

#test
{
    {
        struct(T) LocalBox
        {
            value: T
        }

        let intBox: LocalBox's32 = {value: 42}
        let boolBox: LocalBox'bool = {value: true}

        #assert(#typeof(intBox.value) == s32)
        #assert(#typeof(boolBox.value) == bool)
        @assert(intBox.value == 42)
        @assert(boolBox.value == true)
    }
    {
        struct(T, N: s32) LocalBuffer
        {
            values: [N] T
        }

        let buffer: LocalBuffer'(u16, 3) = {values: [1'u16, 2, 3]}
        #assert(#typeof(buffer.values) == #type [3] u16)
        @assert(buffer.values[0] == 1'u16)
        @assert(buffer.values[2] == 3'u16)
    }
}

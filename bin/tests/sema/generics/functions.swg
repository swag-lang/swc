#global fileprivate

func(T) identity(value: T)->T => value
func(T = s32) defaultTypeValue()->T => 42
func(N: s32 = 3) defaultConstValue()->s32 => N
func(T, N: s32) arrayCount(values: [N] T)->s32 => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

struct(T, N: s32) Buffer
{
    values: [N] T
}

func(T, N: s32) bufferCount(buffer: Buffer'(T, N))->s32 => N

#test
{
    #assert(identity'(s32)(42) == 42)
    #assert(identity'(bool)(true) == true)
    #assert(identity(12'u16) == 12'u16)
}

#test
{
    #assert(#typeof(defaultTypeValue()) == s32)
    #assert(defaultTypeValue() == 42)
    #assert(#typeof(defaultTypeValue'(f64)()) == f64)
    #assert(defaultTypeValue'(f64)() == 42.0)
}

#test
{
    #assert(defaultConstValue() == 3)
    #assert(defaultConstValue'(10)() == 10)
}

#test
{
    let values: [4] u16 = [10'u16, 20, 30, 40]
    let pair: [2] s32 = [1, 2]

    #assert(arrayCount'(u16, 4)(values) == 4)
    #assert(arrayCount(values) == 4)
    #assert(partialCount'(s32)(pair) == 2)
}

#test
{
    let buffer: Buffer'(u16, 4)

    #assert(#typeof(buffer.values) == #type [4] u16)
    #assert(bufferCount'(u16, 4)(buffer) == 4)
}

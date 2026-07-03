#global private

func(T) identity(value: T)->T => value
func(T = s32) withDefault()->T => 42
func(T, N: s32) arrayIdentity(values: [N] T)->[N] T => values

struct(T)
Box
{
    value: T
}

struct(A, B)
Pair
{
    first:  A
    second: B
}

struct(T)
Wrapper
{
    inner: Box'T
}

#assert(#typeof(identity'(s32)(0)) == s32)
#assert(#typeof(identity'(bool)(true)) == bool)
#assert(#typeof(identity(42)) == s32)
#assert(#typeof(identity(10'u8)) == u8)
#assert(#typeof(withDefault()) == s32)
#assert(#typeof(withDefault'(f64)()) == f64)

#test
{
    let ints: [3] s32 = [1, 2, 3]
    let floats: [2] f64 = [1.0, 2.0]

    let ints2 = arrayIdentity(ints)
    let floats2 = arrayIdentity(floats)

    #assert(#typeof(ints2) == #type [3] s32)
    #assert(#typeof(floats2) == #type [2] f64)
    @assert(ints2[0] == 1)
    @assert(ints2[2] == 3)
    @assert(floats2[0] == 1.0'f64)
    @assert(floats2[1] == 2.0'f64)
}

#test
{
    let wrap: Wrapper's32 = {inner: {value: 12}}
    let pair: Pair'(Box's32, Box'string) = {first: {value: 7}, second: {value: "ok"}}
    let deep: Box'(Box'(Box'bool)) = {value: {value: {value: true}}}

    #assert(#typeof(wrap.inner.value) == s32)
    #assert(#typeof(pair.first.value) == s32)
    #assert(#typeof(pair.second.value) == string)
    #assert(#typeof(deep.value.value.value) == bool)
    @assert(wrap.inner.value == 12)
    @assert(pair.first.value == 7)
    @assert(pair.second.value == "ok")
    @assert(deep.value.value.value)
}

#test
{
    let b1: Box's32 = {value: 1}
    let b2: Box's32 = {value: 2}
    let p1: Pair'(s32, f64) = {first: 1, second: 2.5}

    #assert(#typeof(b1) == #typeof(b2))
    #assert(#typeof(b1) == Box's32)
    #assert(#typeof(p1) == Pair'(s32, f64))
    @assert(b1.value == 1)
    @assert(b2.value == 2)
    @assert(p1.first == 1)
    @assert(p1.second == 2.5'f64)
}

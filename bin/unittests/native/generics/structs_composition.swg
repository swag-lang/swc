#global fileprivate

struct(T) Box
{
    value: T
}

struct(T) Wrapper
{
    item: Box'T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

struct(T, N: s32) DoubleBuffer
{
    first: Buffer'(T, N)
    second: Buffer'(T, N)
}

struct(A, B) Pair
{
    first: A
    second: B
}

struct(A, B, C) Triple
{
    a: A
    b: B
    c: C
}

struct(T) DeepWrapper
{
    inner: Wrapper'T
}

struct(T, N: s32) BoxArray
{
    boxes: [N] Box'T
}

func(T) swapPair(p: Pair'(T, T))->Pair'(T, T)
{
    var result: Pair'(T, T)
    result.first = p.second
    result.second = p.first
    return result
}

#test
{
    let wrapped: Wrapper'string = {item: {value: "nested"}}
    @assert(wrapped.item.value == "nested")
    #assert(#typeof(wrapped.item.value) == string)

    let deep: DeepWrapper's32 = {inner: {item: {value: 99}}}
    @assert(deep.inner.item.value == 99)

    let deepText: DeepWrapper'string = {inner: {item: {value: "deep"}}}
    @assert(deepText.inner.item.value == "deep")
}

#test
{
    let first: Buffer'(u8, 3) = {values: [1'u8, 2, 3]}
    let second: Buffer'(u8, 3) = {values: [4'u8, 5, 6]}
    let doubled: DoubleBuffer'(u8, 3) = {first: first, second: second}

    @assert(doubled.first.values[0] == 1'u8)
    @assert(doubled.second.values[2] == 6'u8)
    #assert(#typeof(doubled.first.values) == #type [3] u8)
    #assert(#typeof(doubled.second.values) == #type [3] u8)
}

#test
{
    let p: Pair'(s32, f64) = {first: 1, second: 2.5}
    @assert(p.first == 1)
    @assert(p.second == 2.5)

    let p2: Pair'(string, bool) = {first: "yes", second: true}
    @assert(p2.first == "yes")
    @assert(p2.second == true)

    let t: Triple'(s32, f64, bool) = {a: 10, b: 3.14, c: false}
    @assert(t.a == 10)
    @assert(t.b == 3.14)
    @assert(t.c == false)
}

#test
{
    let p: Pair'(s32, s32) = {first: 10, second: 20}
    let swapped = swapPair'(s32)(p)
    @assert(swapped.first == 20)
    @assert(swapped.second == 10)

    let names: Pair'(string, string) = {first: "left", second: "right"}
    let swappedNames = swapPair'(string)(names)
    @assert(swappedNames.first == "right")
    @assert(swappedNames.second == "left")
}

#test
{
    let nested: Pair'(Pair'(s32, s32), Pair'(f64, f64)) = {
        first: {first: 1, second: 2},
        second: {first: 3.0, second: 4.0}}

    @assert(nested.first.first == 1)
    @assert(nested.first.second == 2)
    @assert(nested.second.first == 3.0)
    @assert(nested.second.second == 4.0)
}

#test
{
    let ba: BoxArray'(s32, 3) = {boxes: [{value: 1}, {value: 2}, {value: 3}]}
    @assert(ba.boxes[0].value == 1)
    @assert(ba.boxes[1].value == 2)
    @assert(ba.boxes[2].value == 3)
}

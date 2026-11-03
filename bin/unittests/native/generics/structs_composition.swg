#global private

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
    first:  Buffer'(T, N)
    second: Buffer'(T, N)
}

struct(A, B) Pair
{
    first:  A
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
    result.first  = p.second
    result.second = p.first
    return result
}

#test
{
    let wrapped: Wrapper'string = {item: {value: "nested"}}
    Swag.require(wrapped.item.value == "nested")
    #assert(#typeof(wrapped.item.value) == string)

    let deep: DeepWrapper's32 = {inner: {item: {value: 99}}}
    Swag.require(deep.inner.item.value == 99)

    let deepText: DeepWrapper'string = {inner: {item: {value: "deep"}}}
    Swag.require(deepText.inner.item.value == "deep")
}

#test
{
    let first:   Buffer'(u8, 3)       = {values: [1'u8, 2, 3]}
    let second:  Buffer'(u8, 3)       = {values: [4'u8, 5, 6]}
    let doubled: DoubleBuffer'(u8, 3) = {first: first, second: second}

    Swag.require(doubled.first.values[0] == 1'u8)
    Swag.require(doubled.second.values[2] == 6'u8)
    #assert(#typeof(doubled.first.values) == #type [3] u8)
    #assert(#typeof(doubled.second.values) == #type [3] u8)
}

#test
{
    let p: Pair'(s32, f64) = {first: 1, second: 2.5}
    Swag.require(p.first == 1)
    Swag.require(p.second == 2.5)

    let p2: Pair'(string, bool) = {first: "yes", second: true}
    Swag.require(p2.first == "yes")
    Swag.require(p2.second == true)

    let t: Triple'(s32, f64, bool) = {a: 10, b: 3.14, c: false}
    Swag.require(t.a == 10)
    Swag.require(t.b == 3.14)
    Swag.require(t.c == false)
}

#test
{
    let p: Pair'(s32, s32) = {first: 10, second: 20}
    let swapped = swapPair'(s32)(p)
    Swag.require(swapped.first == 20)
    Swag.require(swapped.second == 10)

    let names: Pair'(string, string) = {first: "left", second: "right"}
    let swappedNames = swapPair'(string)(names)
    Swag.require(swappedNames.first == "right")
    Swag.require(swappedNames.second == "left")
}

#test
{
    let nested: Pair'(Pair'(s32, s32), Pair'(f64, f64)) = {
        first: {first: 1, second: 2},
        second: {first: 3.0, second: 4.0}}

    Swag.require(nested.first.first == 1)
    Swag.require(nested.first.second == 2)
    Swag.require(nested.second.first == 3.0)
    Swag.require(nested.second.second == 4.0)
}

#test
{
    let ba: BoxArray'(s32, 3) = {boxes: [{value: 1}, {value: 2}, {value: 3}]}
    Swag.require(ba.boxes[0].value == 1)
    Swag.require(ba.boxes[1].value == 2)
    Swag.require(ba.boxes[2].value == 3)
}

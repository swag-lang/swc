#global fileprivate

// --- Basic generic struct ---

struct(T) Box
{
    value: T
}

// --- Multiple params: type + const ---

struct(T, N: s32) Buffer
{
    values: [N] T
}

// --- Nested generic composition ---

struct(T) Wrapper
{
    item: Box'T
}

struct(T, N: s32) DoubleBuffer
{
    first: Buffer'(T, N)
    second: Buffer'(T, N)
}

// --- Default const parameter ---

struct(T, N: s32 = 2) DefaultBuffer
{
    values: [N] T
}

// --- Default type parameter ---

struct(T = s32) DefaultBox
{
    value: T
}

// --- Multiple type parameters ---

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

// --- Deeply nested generics ---

struct(T) DeepWrapper
{
    inner: Wrapper'T
}

// --- Generic struct with pointer field ---

struct(T) PtrHolder
{
    ptr: *T
}

// --- Generic struct with array of generic structs ---

struct(T, N: s32) BoxArray
{
    boxes: [N] Box'T
}

// --- Generic functions working with generic structs ---

func(T, N: s32) bufferCount(buffer: Buffer'(T, N))->s32 => N
func(T) unbox(box: Box'T)->T => box.value

func sumFour(buffer: Buffer'(s32, 4))->s32
{
    return buffer.values[0] + buffer.values[1] + buffer.values[2] + buffer.values[3]
}

func(T) swapPair(p: Pair'(T, T))->Pair'(T, T)
{
    var result: Pair'(T, T)
    result.first = p.second
    result.second = p.first
    return result
}

// --- Basic instantiation and field access ---

#test
{
    let stringBox: Box'string = {value: "swag"}
    let intBox: Box's32 = {value: 42}
    let boolBox: Box'bool = {value: true}
    let floatBox: Box'f64 = {value: 3.14}

    @assert(stringBox.value == "swag")
    @assert(intBox.value == 42)
    @assert(boolBox.value == true)
    @assert(floatBox.value == 3.14)
}

// --- Buffer with type + const ---

#test
{
    let buffer: Buffer'(s32, 4) = {values: [1, 2, 3, 4]}
    @assert(buffer.values[0] == 1)
    @assert(buffer.values[3] == 4)
    @assert(bufferCount'(s32, 4)(buffer) == 4)
    @assert(sumFour(buffer) == 10)

    let small: Buffer'(u8, 2) = {values: [10'u8, 20]}
    @assert(small.values[0] == 10'u8)
    @assert(small.values[1] == 20'u8)
}

// --- Nested generics ---

#test
{
    let wrapped: Wrapper'string = {item: {value: "nested"}}
    @assert(wrapped.item.value == "nested")

    #assert(#typeof(wrapped.item.value) == string)

    let deep: DeepWrapper's32 = {inner: {item: {value: 99}}}
    @assert(deep.inner.item.value == 99)
}

// --- DoubleBuffer ---

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

// --- Default parameters ---

#test
{
    let partial: DefaultBuffer'u16 = {values: [10'u16, 20]}
    @assert(partial.values[0] == 10'u16)
    @assert(partial.values[1] == 20'u16)
    #assert(#typeof(partial.values) == #type [2] u16)

    let explicit: DefaultBuffer'(s32, 3) = {values: [1, 2, 3]}
    @assert(explicit.values[2] == 3)

    let defBox: DefaultBox = {value: 42}
    @assert(defBox.value == 42)
    #assert(#typeof(defBox.value) == s32)

    let defBoxF: DefaultBox'f64 = {value: 1.5}
    @assert(defBoxF.value == 1.5)
    #assert(#typeof(defBoxF.value) == f64)
}

// --- Multiple type parameters ---

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

// --- Pair of same type ---

#test
{
    let p: Pair'(s32, s32) = {first: 10, second: 20}
    let swapped = swapPair'(s32)(p)
    @assert(swapped.first == 20)
    @assert(swapped.second == 10)
}

// --- Generic struct with pointer field ---

#test
{
    var x: s32 = 42
    let holder: PtrHolder's32 = {ptr: &x}
    @assert(dref holder.ptr == 42)

    var y: f64 = 1.5
    let holderF: PtrHolder'f64 = {ptr: &y}
    @assert(dref holderF.ptr == 1.5)
}

// --- Nested pair (Pair of Pairs) ---

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

// @bug Generic functions returning generic structs are not working yet.
// func(T) makeBox(value: T)->Box'T
// {
//     return {value: value}
// }
//
// #test
// {
//     let b = makeBox(42)
//     @assert(b.value == 42)
//
//     let b2 = makeBox("hello")
//     @assert(b2.value == "hello")
//
//     let b3 = makeBox(true)
//     @assert(b3.value == true)
// }

// --- Unbox generic function ---

#test
{
    let b: Box's32 = {value: 99}
    @assert(unbox(b) == 99)

    let b2: Box'string = {value: "unboxed"}
    @assert(unbox(b2) == "unboxed")
}

// --- Box array ---

#test
{
    let ba: BoxArray'(s32, 3) = {boxes: [{value: 1}, {value: 2}, {value: 3}]}
    @assert(ba.boxes[0].value == 1)
    @assert(ba.boxes[1].value == 2)
    @assert(ba.boxes[2].value == 3)
}

// --- Generic struct used as function parameter with inference ---

func(T) boxValue(box: Box'T)->T => box.value

#test
{
    let b: Box's32 = {value: 77}
    @assert(boxValue(b) == 77)

    let s: Box'string = {value: "works"}
    @assert(boxValue(s) == "works")
}

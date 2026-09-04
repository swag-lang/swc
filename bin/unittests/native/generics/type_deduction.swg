#global private

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

struct(A, B) Pair
{
    first:  A
    second: B
}

// Deduction from generic struct argument
func(T) unbox(box: Box'T)->T => box.value

func(T, N: s32) bufferFirst(buf: Buffer'(T, N))->T => buf.values[0]
func(T, N: s32) bufferLast(buf: Buffer'(T, N))->T  => buf.values[N - 1]
func(T, N: s32) bufferLen(buf: Buffer'(T, N))->s32 => N

// Deduction from Pair
func(A, B) pairFirst(p: Pair'(A, B))->A  => p.first
func(A, B) pairSecond(p: Pair'(A, B))->B => p.second

// Deduction from pointer
func(T) readPtr(ptr: *T)->T => ptr[]
func(T) writePtr(ptr: *T, value: T) { ptr[] = value }

// Deduction from array
func(T) firstOf2(arr: [2] T)->T => arr[0]
func(T) firstOf3(arr: [3] T)->T => arr[0]

// Deduction combining explicit and implicit
func(T, N: s32) makeBuffer(value: T)->[N] T
{
    var result: [N] T
    for var i = 0; i < N; i += 1 do
        result[i] = value
    return result
}

// Multi-param deduction from two generic struct args
func(A, B) zipBoxes(a: Box'A, b: Box'B)->Pair'(A, B)
{
    return {first: a.value, second: b.value}
}

// Deduction from mixed: one explicit, one deduced
func(T) boxedIdentity(box: Box'T)->Box'T => box

// Multiple args of same type (deduction must agree)
func(T) larger(a: T, b: T)->T
{
    if a > b do
        return a
    return b
}

func(T) smaller(a: T, b: T)->T
{
    if a < b do
        return a
    return b
}

// Deduction through return type use
func(T) makeBox(value: T)->Box'T
{
    return {value: value}
}

func(T) makePair(a: T, b: T)->Pair'(T, T)
{
    return {first: a, second: b}
}

// --- Tests ---

// Deduction from generic struct arg
#test
{
    let b: Box's32 = {value: 42}
    Swag.assert(unbox(b) == 42)

    let bs: Box'string = {value: "deduced"}
    Swag.assert(unbox(bs) == "deduced")

    let bf: Box'f64 = {value: 1.5}
    Swag.assert(unbox(bf) == 1.5)
}

// Deduction from Buffer (both T and N)
#test
{
    let buf: Buffer'(s32, 3) = {values: [10, 20, 30]}
    Swag.assert(bufferFirst(buf) == 10)
    Swag.assert(bufferLast(buf) == 30)
    Swag.assert(bufferLen(buf) == 3)

    let buf2: Buffer'(u8, 2) = {values: [5'u8, 15]}
    Swag.assert(bufferFirst(buf2) == 5'u8)
    Swag.assert(bufferLast(buf2) == 15'u8)
    Swag.assert(bufferLen(buf2) == 2)
}

// Deduction from Pair (two different types)
#test
{
    let p: Pair'(s32, f64) = {first: 1, second: 2.5}
    Swag.assert(pairFirst(p) == 1)
    Swag.assert(pairSecond(p) == 2.5)

    let p2: Pair'(string, bool) = {first: "ok", second: true}
    Swag.assert(pairFirst(p2) == "ok")
    Swag.assert(pairSecond(p2) == true)
}

// Deduction from pointer type
#test
{
    var x: s32 = 99
    Swag.assert(readPtr(&x) == 99)
    writePtr(&x, 77)
    Swag.assert(x == 77)

    var y: f64 = 3.14
    Swag.assert(readPtr(&y) == 3.14)
}

// Deduction from fixed array
#test
{
    let a2: [2] s32 = [10, 20]
    Swag.assert(firstOf2(a2) == 10)

    let a3: [3] f64 = [1.5, 2.5, 3.5]
    Swag.assert(firstOf3(a3) == 1.5)

    let b2: [2] u16 = [100'u16, 200]
    Swag.assert(firstOf2(b2) == 100'u16)
}

// Partial explicit + deduction
#test
{
    let arr = makeBuffer'(s32, 4)(7)
    Swag.assert(arr[0] == 7)
    Swag.assert(arr[3] == 7)

    let barr = makeBuffer'(bool, 2)(true)
    Swag.assert(barr[0] == true)
    Swag.assert(barr[1] == true)
}

// Multi-arg deduction from two generic structs
#test
{
    let a: Box's32    = {value: 10}
    let b: Box'string = {value: "zip"}
    let pair          = zipBoxes(a, b)
    Swag.assert(pair.first == 10)
    Swag.assert(pair.second == "zip")
}

// Same-type multi-arg deduction
#test
{
    Swag.assert(larger(3, 7) == 7)
    Swag.assert(larger(7, 3) == 7)
    Swag.assert(smaller(3, 7) == 3)
    Swag.assert(smaller(7, 3) == 3)

    Swag.assert(larger(1.5, 2.5) == 2.5)
    Swag.assert(smaller(1.5, 2.5) == 1.5)
}

// Deduction on makeBox (return type is generic struct)
#test
{
    let b = makeBox(42)
    Swag.assert(b.value == 42)
    #assert(#typeof(b.value) == s32)

    let b2 = makeBox("hello")
    Swag.assert(b2.value == "hello")
    #assert(#typeof(b2.value) == string)

    let b3 = makeBox(true)
    Swag.assert(b3.value == true)
    #assert(#typeof(b3.value) == bool)
}

// Deduction on makePair
#test
{
    let p = makePair(10, 20)
    Swag.assert(p.first == 10)
    Swag.assert(p.second == 20)
    #assert(#typeof(p.first) == s32)

    let p2 = makePair(1.0'f64, 2.0'f64)
    Swag.assert(p2.first == 1.0'f64)
    Swag.assert(p2.second == 2.0'f64)
    #assert(#typeof(p2.first) == f64)
}

// Explicit vs deduced produce same result
#test
{
    let deduced  = unbox(Box'string{value: "test"})
    let explicit = unbox'(string)(Box'string{value: "test"})
    Swag.assert(deduced == explicit)
    Swag.assert(deduced == "test")
}

// Chained deduction: makeBox of makeBox
#test
{
    let box = makeBox(makeBox(42))
    Swag.assert(box.value.value == 42)

    let box2 = makeBox(makeBox("hello"))
    Swag.assert(box2.value.value == "hello")
}

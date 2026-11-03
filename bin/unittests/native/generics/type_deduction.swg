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
    Swag.require(unbox(b) == 42)

    let bs: Box'string = {value: "deduced"}
    Swag.require(unbox(bs) == "deduced")

    let bf: Box'f64 = {value: 1.5}
    Swag.require(unbox(bf) == 1.5)
}

// Deduction from Buffer (both T and N)
#test
{
    let buf: Buffer'(s32, 3) = {values: [10, 20, 30]}
    Swag.require(bufferFirst(buf) == 10)
    Swag.require(bufferLast(buf) == 30)
    Swag.require(bufferLen(buf) == 3)

    let buf2: Buffer'(u8, 2) = {values: [5'u8, 15]}
    Swag.require(bufferFirst(buf2) == 5'u8)
    Swag.require(bufferLast(buf2) == 15'u8)
    Swag.require(bufferLen(buf2) == 2)
}

// Deduction from Pair (two different types)
#test
{
    let p: Pair'(s32, f64) = {first: 1, second: 2.5}
    Swag.require(pairFirst(p) == 1)
    Swag.require(pairSecond(p) == 2.5)

    let p2: Pair'(string, bool) = {first: "ok", second: true}
    Swag.require(pairFirst(p2) == "ok")
    Swag.require(pairSecond(p2) == true)
}

// Deduction from pointer type
#test
{
    var x: s32 = 99
    Swag.require(readPtr(&x) == 99)
    writePtr(&x, 77)
    Swag.require(x == 77)

    var y: f64 = 3.14
    Swag.require(readPtr(&y) == 3.14)
}

// Deduction from fixed array
#test
{
    let a2: [2] s32 = [10, 20]
    Swag.require(firstOf2(a2) == 10)

    let a3: [3] f64 = [1.5, 2.5, 3.5]
    Swag.require(firstOf3(a3) == 1.5)

    let b2: [2] u16 = [100'u16, 200]
    Swag.require(firstOf2(b2) == 100'u16)
}

// Partial explicit + deduction
#test
{
    let arr = makeBuffer'(s32, 4)(7)
    Swag.require(arr[0] == 7)
    Swag.require(arr[3] == 7)

    let barr = makeBuffer'(bool, 2)(true)
    Swag.require(barr[0] == true)
    Swag.require(barr[1] == true)
}

// Multi-arg deduction from two generic structs
#test
{
    let a: Box's32    = {value: 10}
    let b: Box'string = {value: "zip"}
    let pair          = zipBoxes(a, b)
    Swag.require(pair.first == 10)
    Swag.require(pair.second == "zip")
}

// Same-type multi-arg deduction
#test
{
    Swag.require(larger(3, 7) == 7)
    Swag.require(larger(7, 3) == 7)
    Swag.require(smaller(3, 7) == 3)
    Swag.require(smaller(7, 3) == 3)

    Swag.require(larger(1.5, 2.5) == 2.5)
    Swag.require(smaller(1.5, 2.5) == 1.5)
}

// Deduction on makeBox (return type is generic struct)
#test
{
    let b = makeBox(42)
    Swag.require(b.value == 42)
    #assert(#typeof(b.value) == s32)

    let b2 = makeBox("hello")
    Swag.require(b2.value == "hello")
    #assert(#typeof(b2.value) == string)

    let b3 = makeBox(true)
    Swag.require(b3.value == true)
    #assert(#typeof(b3.value) == bool)
}

// Deduction on makePair
#test
{
    let p = makePair(10, 20)
    Swag.require(p.first == 10)
    Swag.require(p.second == 20)
    #assert(#typeof(p.first) == s32)

    let p2 = makePair(1.0'f64, 2.0'f64)
    Swag.require(p2.first == 1.0'f64)
    Swag.require(p2.second == 2.0'f64)
    #assert(#typeof(p2.first) == f64)
}

// Explicit vs deduced produce same result
#test
{
    let deduced  = unbox(Box'string{value: "test"})
    let explicit = unbox'(string)(Box'string{value: "test"})
    Swag.require(deduced == explicit)
    Swag.require(deduced == "test")
}

// Chained deduction: makeBox of makeBox
#test
{
    let box = makeBox(makeBox(42))
    Swag.require(box.value.value == 42)

    let box2 = makeBox(makeBox("hello"))
    Swag.require(box2.value.value == "hello")
}

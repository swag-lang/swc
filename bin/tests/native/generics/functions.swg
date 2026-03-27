#global fileprivate

// --- Basic generic functions ---

func(T) echo(value: T)->T => value
func(T = s32) defaultValue()->T => 11
func(N: s32 = 3) bias(value: s32)->s32 => value + N
func(T, N: s32) arrayCount(values: [N] T)->s32 => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

// --- Type inference and return type ---

func(T) double(value: T)->T => value + value
func(T) first(a: T, b: T)->T => a
func(T) isZero(value: T)->bool => value == 0

// --- Nested generic calls ---

func(T) wrapEcho(value: T)->T => echo(value)
func(T) doubleEcho(value: T)->T => echo(echo(value))

// --- Generic with pointer and reference ---

func(T) deref(ptr: *T)->T => dref ptr
func(T) addrValue(value: *T)->*T => value

// --- Multiple type parameters ---

func(A, B) makePairFirst(a: A, b: B)->A => a
func(A, B) makePairSecond(a: A, b: B)->B => b

// --- Const generic expressions ---

func(N: s32) constSquare()->s32 => N * N
func(N: s32, M: s32) constSum()->s32 => N + M
func(N: s32 = 5, M: s32 = 10) constDefaults()->s32 => N + M

// --- Compile-time type assertions ---

#assert(#typeof(defaultValue()) == s32)
#assert(#typeof(defaultValue'(f64)()) == f64)
#assert(#typeof(echo'(bool)(true)) == bool)
#assert(#typeof(makePairFirst'(s32, f64)(1, 2.0)) == s32)
#assert(#typeof(makePairSecond'(s32, f64)(1, 2.0)) == f64)

// --- Basic explicit and inferred calls ---

#test
{
    let values: [4] u16 = [10'u16, 20, 30, 40]
    let pair: [2] s32 = [1, 2]

    @assert(echo'(s32)(7) == 7)
    @assert(echo(true) == true)
    @assert(echo(3.14) == 3.14)
    @assert(echo'(u8)(255'u8) == 255'u8)
    @assert(defaultValue() == 11)
    @assert(defaultValue'(f64)() == 11.0)
    @assert(bias(7) == 10)
    @assert(bias'(10)(7) == 17)
    @assert(bias'(0)(7) == 7)
    @assert(arrayCount'(u16, 4)(values) == 4)
    @assert(arrayCount(values) == 4)
    @assert(partialCount'(s32)(pair) == 2)
}

// --- Type inference from arguments ---

#test
{
    @assert(echo(42) == 42)
    @assert(echo(true) == true)
    @assert(echo(3.14) == 3.14)
    @assert(echo("hello") == "hello")

    @assert(double(5) == 10)
    @assert(double(2.5) == 5.0)

    // @bug Repeated type parameter inference does not resolve for generic calls yet.
    // @assert(first(1, 2) == 1)
    // @assert(first("a", "b") == "a")

    @assert(isZero(0) == true)
    @assert(isZero(1) == false)
    @assert(isZero(0.0) == true)
}

// --- Nested generic calls ---

#test
{
    @assert(wrapEcho(42) == 42)
    @assert(wrapEcho(true) == true)
    @assert(wrapEcho("nested") == "nested")

    @assert(doubleEcho(99) == 99)
    @assert(doubleEcho(false) == false)
}

// --- Pointer parameters ---

#test
{
    var x: s32 = 42
    @assert(deref(&x) == 42)

    var y: f64 = 3.14
    @assert(deref(&y) == 3.14)

    var b: bool = true
    @assert(deref(&b) == true)

    @assert(addrValue(&x) == &x)
}

// --- Multiple type parameters ---

#test
{
    // @bug Mixed generic argument inference does not resolve for multi-parameter functions yet.
    // @assert(makePairFirst(1, 2.0) == 1)
    // @assert(makePairSecond(1, 2.0) == 2.0)
    // @assert(makePairFirst(true, "hi") == true)
    // @assert(makePairSecond(true, "hi") == "hi")
    @assert(makePairFirst'(u8, u16)(10'u8, 20'u16) == 10'u8)
    @assert(makePairSecond'(u8, u16)(10'u8, 20'u16) == 20'u16)
}

// --- Const generic parameters ---

#test
{
    @assert(constSquare'(4)() == 16)
    @assert(constSquare'(0)() == 0)
    @assert(constSquare'(7)() == 49)

    @assert(constSum'(3, 4)() == 7)
    @assert(constSum'(0, 0)() == 0)
    @assert(constSum'(100, -50)() == 50)

    @assert(constDefaults() == 15)
    @assert(constDefaults'(1)() == 11)
    @assert(constDefaults'(1, 2)() == 3)
}

// @bug Generic functions with local temporaries and loops are not working yet.
// func(T, N: s32) fillArray(value: T)->[N] T
// {
//     var result: [N] T = undefined
//     for var i = 0; i < N; i += 1 do
//         result[i] = value
//     return result
// }
//
// #test
// {
//     let arr = fillArray'(s32, 3)(7)
//     @assert(arr[0] == 7)
//     @assert(arr[1] == 7)
//     @assert(arr[2] == 7)
//
//     let barr = fillArray'(bool, 2)(true)
//     @assert(barr[0] == true)
//     @assert(barr[1] == true)
// }

// --- Generic function calling another generic with different type ---

func(T) toS32(value: T)->s32 => cast(s32) value
func(T) castAndDouble(value: T)->s32 => toS32(value) * 2

#test
{
    @assert(toS32(3.7) == 3)
    @assert(toS32(true) == 1)
    @assert(castAndDouble(2.5) == 4)
    @assert(castAndDouble(false) == 0)
}

// --- Explicit specialization with same type multiple times ---

#test
{
    @assert(first'(s32)(10, 20) == 10)
    @assert(first'(bool)(true, false) == true)
    @assert(first'(f32)(1.5'f32, 2.5'f32) == 1.5'f32)
}

// @bug Generic functions with local temporaries and loops are not working yet.
// func(T, N: s32) sumN(values: [N] T)->T
// {
//     var total: T = 0
//     for var i = 0; i < N; i += 1 do
//         total += values[i]
//     return total
// }
//
// #test
// {
//     let a: [3] s32 = [10, 20, 30]
//     @assert(sumN(a) == 60)
//
//     let b: [4] f64 = [1.0, 2.0, 3.0, 4.0]
//     @assert(sumN(b) == 10.0)
//
//     let c: [2] u16 = [100'u16, 200]
//     @assert(sumN(c) == 300'u16)
// }

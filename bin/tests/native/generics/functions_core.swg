#global fileprivate

func(T) echo(value: T)->T => value
func(T = s32) defaultValue()->T => 11
func(N: s32 = 3) bias(value: s32)->s32 => value + N
func(T, N: s32) arrayCount(values: [N] T)->s32 => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

func(T) double(value: T)->T => value + value
func(T) first(a: T, b: T)->T => a
func(T) isZero(value: T)->bool => value == 0

func(T) wrapEcho(value: T)->T => echo(value)
func(T) doubleEcho(value: T)->T => echo(echo(value))

func(T) deref(ptr: *T)->T => dref ptr
func(T) addrValue(value: *T)->*T => value

func(A, B) makePairFirst(a: A, b: B)->A => a
func(A, B) makePairSecond(a: A, b: B)->B => b

#assert(#typeof(defaultValue()) == s32)
#assert(#typeof(defaultValue'(f64)()) == f64)
#assert(#typeof(echo'(bool)(true)) == bool)
#assert(#typeof(makePairFirst'(s32, f64)(1, 2.0)) == s32)
#assert(#typeof(makePairSecond'(s32, f64)(1, 2.0)) == f64)
#assert(#typeof(first'(u8)(1'u8, 2)) == u8)

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

#test
{
    @assert(echo(42) == 42)
    @assert(echo(true) == true)
    @assert(echo(3.14) == 3.14)
    @assert(echo("hello") == "hello")

    @assert(double(5) == 10)
    @assert(double(2.5) == 5.0)

    @assert(first(1, 2) == 1)
    @assert(first("a", "b") == "a")

    @assert(isZero(0) == true)
    @assert(isZero(1) == false)
    @assert(isZero(0.0) == true)
}

#test
{
    @assert(wrapEcho(42) == 42)
    @assert(wrapEcho(true) == true)
    @assert(wrapEcho("nested") == "nested")

    @assert(doubleEcho(99) == 99)
    @assert(doubleEcho(false) == false)
    @assert(doubleEcho("echo") == "echo")
}

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

#test
{
    @assert(makePairFirst(1, 2.0) == 1)
    @assert(makePairSecond(1, 2.0) == 2.0)
    @assert(makePairFirst(true, "hi") == true)
    @assert(makePairSecond(true, "hi") == "hi")
    @assert(makePairFirst'(u8, u16)(10'u8, 20'u16) == 10'u8)
    @assert(makePairSecond'(u8, u16)(10'u8, 20'u16) == 20'u16)
    @assert(makePairFirst("left", 123) == "left")
}

#test
{
    @assert(first'(s32)(10, 20) == 10)
    @assert(first'(bool)(true, false) == true)
    @assert(first'(f32)(1.5'f32, 2.5'f32) == 1.5'f32)
}

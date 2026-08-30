#global private

func(T) echo(value: T)->T                            => value
func(T) doubleLeftLiteral(value: T)                  => 2 * value
func(T = s32, V = s32) mixedMultiply(a: T, b: V)     => a * b
func(T = s32) defaultValue()->T                      => 11
func(N: s32 = 3) bias(value: s32)->s32               => value + N
func(T, N: s32) arrayCount(values: [N] T)->s32       => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

func(T) double(value: T)->T    => value + value
func(T) first(a: T, b: T)->T   => a
func(T) isZero(value: T)->bool => value == 0

func(T) wrapEcho(value: T)->T   => echo(value)
func(T) doubleEcho(value: T)->T => echo(echo(value))

func(T) deref(ptr: *T)->T        => ptr[]
func(T) addrValue(value: *T)->*T => value

func(A, B) makePairFirst(a: A, b: B)->A  => a
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
    let pair:   [2] s32 = [1, 2]

    Swag.assert(echo'(s32)(7) == 7)
    Swag.assert(echo(true) == true)
    Swag.assert(echo(3.14) == 3.14)
    Swag.assert(echo'(u8)(255'u8) == 255'u8)
    Swag.assert(doubleLeftLiteral'(s32)(21) == 42)
    Swag.assert(doubleLeftLiteral(2.5'f32) == 5.0'f32)
    Swag.assert(mixedMultiply(1's32, 2'f32) == 2.0'f32)
    Swag.assert(defaultValue() == 11)
    Swag.assert(defaultValue'(f64)() == 11.0)
    Swag.assert(bias(7) == 10)
    Swag.assert(bias'(10)(7) == 17)
    Swag.assert(bias'(0)(7) == 7)
    Swag.assert(arrayCount'(u16, 4)(values) == 4)
    Swag.assert(arrayCount(values) == 4)
    Swag.assert(partialCount'(s32)(pair) == 2)
}

#test
{
    func(T) localDouble(value: T) => 2 * value
    func(T = s32, V = s32) localMixedMultiply(a: T, b: V) => a * b

    Swag.assert(localDouble'(s32)(21) == 42)
    Swag.assert(localDouble(2.5'f32) == 5.0'f32)
    Swag.assert(localMixedMultiply(1's32, 2'f32) == 2.0'f32)
}

#test
{
    Swag.assert(echo(42) == 42)
    Swag.assert(echo(true) == true)
    Swag.assert(echo(3.14) == 3.14)
    Swag.assert(echo("hello") == "hello")

    Swag.assert(double(5) == 10)
    Swag.assert(double(2.5) == 5.0)

    Swag.assert(first(1, 2) == 1)
    Swag.assert(first("a", "b") == "a")

    Swag.assert(isZero(0) == true)
    Swag.assert(isZero(1) == false)
    Swag.assert(isZero(0.0) == true)
}

#test
{
    Swag.assert(wrapEcho(42) == 42)
    Swag.assert(wrapEcho(true) == true)
    Swag.assert(wrapEcho("nested") == "nested")

    Swag.assert(doubleEcho(99) == 99)
    Swag.assert(doubleEcho(false) == false)
    Swag.assert(doubleEcho("echo") == "echo")
}

#test
{
    var x: s32 = 42
    Swag.assert(deref(&x) == 42)

    var y: f64 = 3.14
    Swag.assert(deref(&y) == 3.14)

    var b: bool = true
    Swag.assert(deref(&b) == true)

    Swag.assert(addrValue(&x) == &x)
}

#test
{
    Swag.assert(makePairFirst(1, 2.0) == 1)
    Swag.assert(makePairSecond(1, 2.0) == 2.0)
    Swag.assert(makePairFirst(true, "hi") == true)
    Swag.assert(makePairSecond(true, "hi") == "hi")
    Swag.assert(makePairFirst'(u8, u16)(10'u8, 20'u16) == 10'u8)
    Swag.assert(makePairSecond'(u8, u16)(10'u8, 20'u16) == 20'u16)
    Swag.assert(makePairFirst("left", 123) == "left")
}

#test
{
    Swag.assert(first'(s32)(10, 20) == 10)
    Swag.assert(first'(bool)(true, false) == true)
    Swag.assert(first'(f32)(1.5'f32, 2.5'f32) == 1.5'f32)
}

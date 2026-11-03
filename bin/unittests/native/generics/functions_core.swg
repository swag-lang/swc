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

    Swag.require(echo'(s32)(7) == 7)
    Swag.require(echo(true) == true)
    Swag.require(echo(3.14) == 3.14)
    Swag.require(echo'(u8)(255'u8) == 255'u8)
    Swag.require(doubleLeftLiteral'(s32)(21) == 42)
    Swag.require(doubleLeftLiteral(2.5'f32) == 5.0'f32)
    Swag.require(mixedMultiply(1's32, 2'f32) == 2.0'f32)
    Swag.require(defaultValue() == 11)
    Swag.require(defaultValue'(f64)() == 11.0)
    Swag.require(bias(7) == 10)
    Swag.require(bias'(10)(7) == 17)
    Swag.require(bias'(0)(7) == 7)
    Swag.require(arrayCount'(u16, 4)(values) == 4)
    Swag.require(arrayCount(values) == 4)
    Swag.require(partialCount'(s32)(pair) == 2)
}

#test
{
    func(T) localDouble(value: T) => 2 * value
    func(T = s32, V = s32) localMixedMultiply(a: T, b: V) => a * b

    Swag.require(localDouble'(s32)(21) == 42)
    Swag.require(localDouble(2.5'f32) == 5.0'f32)
    Swag.require(localMixedMultiply(1's32, 2'f32) == 2.0'f32)
}

#test
{
    Swag.require(echo(42) == 42)
    Swag.require(echo(true) == true)
    Swag.require(echo(3.14) == 3.14)
    Swag.require(echo("hello") == "hello")

    Swag.require(double(5) == 10)
    Swag.require(double(2.5) == 5.0)

    Swag.require(first(1, 2) == 1)
    Swag.require(first("a", "b") == "a")

    Swag.require(isZero(0) == true)
    Swag.require(isZero(1) == false)
    Swag.require(isZero(0.0) == true)
}

#test
{
    Swag.require(wrapEcho(42) == 42)
    Swag.require(wrapEcho(true) == true)
    Swag.require(wrapEcho("nested") == "nested")

    Swag.require(doubleEcho(99) == 99)
    Swag.require(doubleEcho(false) == false)
    Swag.require(doubleEcho("echo") == "echo")
}

#test
{
    var x: s32 = 42
    Swag.require(deref(&x) == 42)

    var y: f64 = 3.14
    Swag.require(deref(&y) == 3.14)

    var b: bool = true
    Swag.require(deref(&b) == true)

    Swag.require(addrValue(&x) == &x)
}

#test
{
    Swag.require(makePairFirst(1, 2.0) == 1)
    Swag.require(makePairSecond(1, 2.0) == 2.0)
    Swag.require(makePairFirst(true, "hi") == true)
    Swag.require(makePairSecond(true, "hi") == "hi")
    Swag.require(makePairFirst'(u8, u16)(10'u8, 20'u16) == 10'u8)
    Swag.require(makePairSecond'(u8, u16)(10'u8, 20'u16) == 20'u16)
    Swag.require(makePairFirst("left", 123) == "left")
}

#test
{
    Swag.require(first'(s32)(10, 20) == 10)
    Swag.require(first'(bool)(true, false) == true)
    Swag.require(first'(f32)(1.5'f32, 2.5'f32) == 1.5'f32)
}

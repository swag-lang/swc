#global private

func(T) echo(value: T)->T                            => value
func(T) doubleLeftLiteral(value: T)                  => 2 * value
func(T = s32, V = s32) mixedMultiply(a: T, b: V)     => a * b
func(T = s32) defaultValue()->T                      => 11
func(N: s32 = 3) bias(value: s32)->s32               => value + N
func(T, N: s32) arrayCount(values: [N] T)->s32       => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

#assert(#typeof(defaultValue()) == s32)
#assert(#typeof(defaultValue'(f64)()) == f64)

#test
{
    let values: [4] u16 = [10'u16, 20, 30, 40]
    let pair:   [2] s32 = [1, 2]

    Swag.assert(echo'(s32)(7) == 7)
    Swag.assert(echo(true) == true)
    Swag.assert(doubleLeftLiteral'(s32)(21) == 42)
    Swag.assert(doubleLeftLiteral(2.5'f32) == 5.0'f32)
    Swag.assert(mixedMultiply(1's32, 2'f32) == 2.0'f32)
    Swag.assert(defaultValue() == 11)
    Swag.assert(defaultValue'(f64)() == 11.0)
    Swag.assert(bias(7) == 10)
    Swag.assert(bias'(10)(7) == 17)
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

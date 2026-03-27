#global fileprivate

func(T) echo(value: T)->T => value
func(T = s32) defaultValue()->T => 11
func(N: s32 = 3) bias(value: s32)->s32 => value + N
func(T, N: s32) arrayCount(values: [N] T)->s32 => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

#assert(#typeof(defaultValue()) == s32)
#assert(#typeof(defaultValue'(f64)()) == f64)

#test
{
    let values: [4] u16 = [10'u16, 20, 30, 40]
    let pair: [2] s32 = [1, 2]

    @assert(echo'(s32)(7) == 7)
    @assert(echo(true) == true)
    @assert(defaultValue() == 11)
    @assert(defaultValue'(f64)() == 11.0)
    @assert(bias(7) == 10)
    @assert(bias'(10)(7) == 17)
    @assert(arrayCount'(u16, 4)(values) == 4)
    @assert(arrayCount(values) == 4)
    @assert(partialCount'(s32)(pair) == 2)
}

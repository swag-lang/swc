#global fileprivate

func(N: s32) constSquare()->s32 => N * N
func(N: s32, M: s32) constSum()->s32 => N + M
func(N: s32 = 5, M: s32 = 10) constDefaults()->s32 => N + M

func(T, N: s32) fillArray(value: T)->[N] T
{
    var result: [N] T = undefined
    for var i = 0; i < N; i += 1 do
        result[i] = value
    return result
}

func(T, N: s32) sumN(values: [N] T)->T
{
    var total: T = 0
    for var i = 0; i < N; i += 1 do
        total += values[i]
    return total
}

func(T) toS32(value: T)->s32 => cast(s32) value
func(T) castAndDouble(value: T)->s32 => toS32(value) * 2

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

#test
{
    let arr = fillArray'(s32, 3)(7)
    @assert(arr[0] == 7)
    @assert(arr[1] == 7)
    @assert(arr[2] == 7)

    let barr = fillArray'(bool, 2)(true)
    @assert(barr[0] == true)
    @assert(barr[1] == true)

    let uarr = fillArray'(u16, 4)(9'u16)
    @assert(uarr[0] == 9'u16)
    @assert(uarr[3] == 9'u16)
}

#test
{
    let a: [3] s32 = [10, 20, 30]
    @assert(sumN(a) == 60)

    let b: [4] f64 = [1.0, 2.0, 3.0, 4.0]
    @assert(sumN(b) == 10.0)

    let c: [2] u16 = [100'u16, 200]
    @assert(sumN(c) == 300'u16)

    let d: [3] s64 = [1's64, 2, 3]
    @assert(sumN(d) == 6's64)
}

#test
{
    @assert(toS32(3.7) == 3)
    @assert(toS32(true) == 1)
    @assert(castAndDouble(2.5) == 4)
    @assert(castAndDouble(false) == 0)
    @assert(castAndDouble(5) == 10)
}

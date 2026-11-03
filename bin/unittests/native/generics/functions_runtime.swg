#global private

func(N: s32) constSquare()->s32      => N * N
func(N: s32, M: s32) constSum()->s32 => N + M
func(N: s32 = 5, M: s32 = 10) constDefaults()->s32 => N + M

func(T, N: s32) fillArray(value: T)->[N] T
{
    var result: [N] T
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

func(T) toS32(value: T)->s32         => cast(s32, value)
func(T) castAndDouble(value: T)->s32 => toS32(value) * 2

#test
{
    Swag.require(constSquare'(4)() == 16)
    Swag.require(constSquare'(0)() == 0)
    Swag.require(constSquare'(7)() == 49)

    Swag.require(constSum'(3, 4)() == 7)
    Swag.require(constSum'(0, 0)() == 0)
    Swag.require(constSum'(100, -50)() == 50)

    Swag.require(constDefaults() == 15)
    Swag.require(constDefaults'(1)() == 11)
    Swag.require(constDefaults'(1, 2)() == 3)
}

#test
{
    let arr = fillArray'(s32, 3)(7)
    Swag.require(arr[0] == 7)
    Swag.require(arr[1] == 7)
    Swag.require(arr[2] == 7)

    let barr = fillArray'(bool, 2)(true)
    Swag.require(barr[0] == true)
    Swag.require(barr[1] == true)

    let uarr = fillArray'(u16, 4)(9'u16)
    Swag.require(uarr[0] == 9'u16)
    Swag.require(uarr[3] == 9'u16)
}

#test
{
    let a: [3] s32 = [10, 20, 30]
    Swag.require(sumN(a) == 60)

    let b: [4] f64 = [1.0, 2.0, 3.0, 4.0]
    Swag.require(sumN(b) == 10.0)

    let c: [2] u16 = [100'u16, 200]
    Swag.require(sumN(c) == 300'u16)

    let d: [3] s64 = [1's64, 2, 3]
    Swag.require(sumN(d) == 6's64)
}

#test
{
    Swag.require(toS32(3.7) == 3)
    Swag.require(toS32(true) == 1)
    Swag.require(castAndDouble(2.5) == 4)
    Swag.require(castAndDouble(false) == 0)
    Swag.require(castAndDouble(5) == 10)
}

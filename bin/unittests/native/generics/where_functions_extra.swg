#global private

alias Real32 = f32

struct(A, B) Pair
{
    first:  A
    second: B
}

func(T) kind(value: T)->u8
    where T == f32 or T == f64
{
    return 1
}

func(T) kind(value: T)->u8
    where T == s32 or T == s64
{
    return 2
}

func(T) onlyFloat(value: T)->T
    where T == f32 or T == f64
{
    return value
}

func(T) onlyIntegersBlock(value: T)->T
    where
    {
        if T == s32 or T == s64 do
            return true
        return false
    }
{
    return value
}

func(T, N: s32) head(values: [N] T)->T
    where N > 0
    where T == s32 or T == s64
{
    return values[0]
}

func(N: s32) mustBePositive()->s32
    where N > 0
{
    return N
}

func(T = Real32) defaultFloatValue()->T
    where T == f32 or T == f64
{
    return cast(T, 2)
}

func(T, U = T) sameTypePair(left: T, right: U)->U
    where T == U
{
    return right
}

func(T, U = T) sameTypeBlock(left: T, right: U)->bool
    where
    {
        if T == U do
            return true
        return false
    }
{
    return true
}

func(T, U = T) interpolateWithWhere(left: T, right: U, ratio: T)->T
    where T == U
    where T == f32 or T == f64
{
    return left + (right - left) * ratio
}

func(T, U) secondIfLeftIsSigned(pair: Pair'(T, U))->U
    where T == s32 or T == s64
{
    return pair.second
}

func(T, N: s32 = 4) fixedTail(values: [N] T)->T
    where N >= 2
{
    return values[N - 1]
}

struct(T) Wrapper
{
    value: T
}

impl Wrapper
{
    func(U) pairValue(const me, other: U)->U
        where T == f32 and U == s32
    {
        return other
    }

    func(U = T) mirrorType(const me, other: U)->U
        where T == U
    {
        return other
    }

    func copyIfFloat(const me)->T
        where T == f32 or T == f64
    {
        return me.value
    }
}

struct(T, Count: s32) Window
{
    values: [Count] T
}

struct(T, Count: s32) InterpolationWindow
    where Count >= 3
    where T == f32 or T == f64
{
    values: [Count] T
}

impl Window
{
    func(const Index: s32) at(const me)->T
        where Index >= 0
        where Index < Count
    {
        return me.values[Index]
    }

    func(U = T) sameSample(const me, other: U)->U
        where Count > 0
        where T == U
    {
        return other
    }

    func firstIfFloat(const me)->T
        where Count >= 2
        where T == f32 or T == f64
    {
        return me.values[0]
    }
}

impl InterpolationWindow
{
    func midpoint(const me)->T
        where Count >= 3
    {
        return interpolateWithWhere'(T)(me.values[0], me.values[Count - 1], cast(T, 0.5))
    }
}

#test
{
    let values: [3] s32 = [5, 6, 7]
    let fixed:  [4] u8  = [1'u8, 2, 3, 4]

    Swag.require(kind(1.0'f32) == 1)
    Swag.require(kind(1's64) == 2)
    Swag.require(onlyFloat(1.0'f64) == 1.0'f64)
    Swag.require(onlyIntegersBlock(12's32) == 12)
    Swag.require(head(values) == 5)
    Swag.require(mustBePositive'3() == 3)
    Swag.require(defaultFloatValue() == 2.0'f32)
    Swag.require(defaultFloatValue'(f64)() == 2.0'f64)
    Swag.require(fixedTail(fixed) == 4'u8)
}

#test
{
    let signedPair: Pair'(s32, string) = {first: 7, second: "ok"}
    let floatBox:   Wrapper'f32        = {value: 1.5}

    Swag.require(sameTypePair(1's32, 2's32) == 2)
    Swag.require(sameTypePair'(f64)(1.0'f64, 2.0'f64) == 2.0'f64)
    Swag.require(sameTypeBlock(1.5'f32, 2.5'f32))
    Swag.require(interpolateWithWhere(10.0'f32, 20.0'f32, 0.25'f32) == 12.5'f32)
    Swag.require(secondIfLeftIsSigned(signedPair) == "ok")
    Swag.require(floatBox.pairValue's32(99) == 99)
    Swag.require(floatBox.mirrorType(2.5'f32) == 2.5'f32)
    Swag.require(floatBox.copyIfFloat() == 1.5'f32)
}

#test
{
    let floatWindow:  Window'(f32, 3) = {values: [10.0'f32, 20.0, 30.0]}
    let intWindow:    Window'(s32, 3) = {values: [1, 2, 3]}
    let interpolated: InterpolationWindow'(f64, 3) = {values: [10.0'f64, 20.0, 30.0]}

    Swag.require(floatWindow.at'1() == 20.0'f32)
    Swag.require(intWindow.at'2() == 3)
    Swag.require(floatWindow.sameSample(77.0'f32) == 77.0'f32)
    Swag.require(intWindow.sameSample(9's32) == 9)
    Swag.require(floatWindow.firstIfFloat() == 10.0'f32)
    Swag.require(interpolated.midpoint() == 20.0'f64)
}

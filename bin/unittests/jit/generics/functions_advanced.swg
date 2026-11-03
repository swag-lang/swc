#global private

func(T) identity(value: T)->T => value
func(T) double(value: T)->T   => value + value

func(T) minVal(a: T, b: T)->T
{
    if a < b do
        return a
    return b
}

func(T) maxVal(a: T, b: T)->T
{
    if a > b do
        return a
    return b
}

func(T) clamp(value: T, lo: T, hi: T)->T
{
    return maxVal(lo, minVal(value, hi))
}

func(T) absValue(value: T)->T
{
    if value < 0 do
        return -value
    return value
}

// Chained generics
func(T) addOne(value: T)->T => value + 1
func(T) addTwo(value: T)->T => addOne(addOne(value))

// Cast between types
func(A, B) castTo(value: A)->B => cast(B, value)

// Generic with const params and expressions
func(N: s32, M: s32) constProduct()->s32 => N * M
func(N: s32) constDoubled()->s32         => N + N

struct(T) Box
{
    value: T
}

func(T) makeBox(value: T)->Box'T
{
    return {value: value}
}

func(T) unbox(box: Box'T)->T => box.value

// Compile-time type assertions
#assert(#typeof(identity(42)) == s32)
#assert(#typeof(identity(true)) == bool)
#assert(#typeof(identity(3.14)) == f64)
#assert(#typeof(double(5)) == s32)
#assert(#typeof(double(1.0'f64)) == f64)
#assert(#typeof(castTo'(s32, f64)(1)) == f64)
#assert(#typeof(castTo'(bool, s32)(true)) == s32)
#assert(#typeof(makeBox(42)) == Box's32)
#assert(#typeof(makeBox("hi")) == Box'(string))
#assert(#typeof(makeBox(true).value) == bool)

#test
{
    Swag.require(minVal(3, 7) == 3)
    Swag.require(maxVal(3, 7) == 7)
    Swag.require(clamp(5, 0, 10) == 5)
    Swag.require(clamp(-5, 0, 10) == 0)
    Swag.require(clamp(15, 0, 10) == 10)
}

#test
{
    Swag.require(absValue(-5) == 5)
    Swag.require(absValue(5) == 5)
    Swag.require(absValue(0) == 0)
    Swag.require(absValue(-3.5) == 3.5)
}

#test
{
    Swag.require(addTwo(0) == 2)
    Swag.require(addTwo(10) == 12)
    Swag.require(addTwo(1.5) == 3.5)
}

#test
{
    Swag.require(castTo'(s32, f64)(42) == 42.0)
    Swag.require(castTo'(bool, s32)(true) == 1)
    Swag.require(castTo'(f64, s32)(3.7) == 3)
}

#test
{
    Swag.require(constProduct'(3, 4)() == 12)
    Swag.require(constProduct'(0, 100)() == 0)
    Swag.require(constDoubled'(7)() == 14)
}

#test
{
    let b = makeBox(99)
    Swag.require(b.value == 99)
    Swag.require(unbox(b) == 99)

    let b2 = makeBox(makeBox(42))
    Swag.require(b2.value.value == 42)
    Swag.require(unbox(b2).value == 42)
}

#global private

// Generic with control flow (if/else)
func(T) clampPositive(value: T)->T
{
    if value < 0 do
        return 0
    return value
}

// Generic with loop accumulation
func(T, N: s32) sum(values: [N] T)->T
{
    var total: T = 0
    for var i = 0; i < N; i += 1 do
        total += values[i]
    return total
}

// Generic with loop and conditional
func(T, N: s32) countPositive(values: [N] T)->s32
{
    var count: s32 = 0
    for var i = 0; i < N; i += 1
    {
        if values[i] > 0 do
            count += 1
    }
    return count
}

// Generic calling another generic with same type
func(T) addOne(value: T)->T  => value + 1
func(T) addTwo(value: T)->T  => addOne(addOne(value))
func(T) addFour(value: T)->T => addTwo(addTwo(value))

// Generic calling another generic with different type
func(T) toF64(value: T)->f64       => cast(f64, value)
func(T) doubleAsF64(value: T)->f64 => toF64(value) * 2.0

// Generic with multiple return paths
func(T) absValue(value: T)->T
{
    if value < 0 do
        return -value
    return value
}

// Generic min/max
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

// Generic clamp using other generics
func(T) clamp(value: T, lo: T, hi: T)->T
{
    return maxVal(lo, minVal(value, hi))
}

// Concrete-typed higher-order functions
func applyS32(value: s32, transform: func(s32)->s32)->s32 => transform(value)
func applyF64(value: f64, transform: func(f64)->f64)->f64 => transform(value)

func doubleS32(x: s32)->s32 => x * 2
func negateS32(x: s32)->s32 => -x
func doubleF64(x: f64)->f64 => x * 2.0

// Concrete-typed map over array
func mapS32x3(values: [3] s32, transform: func(s32)->s32)->[3] s32
{
    var result: [3] s32
    for var i = 0; i < 3; i += 1 do
        result[i] = transform(values[i])
    return result
}

// Concrete-typed reduce
func reduceS32x4(values: [4] s32, initial: s32, combine: func(s32, s32)->s32)->s32
{
    var acc = initial
    for var i = 0; i < 4; i += 1 do
        acc = combine(acc, values[i])
    return acc
}

func addS32(a: s32, b: s32)->s32 => a + b
func mulS32(a: s32, b: s32)->s32 => a * b

// Generic with cast from one type param to another
func(A, B) castTo(value: A)->B => cast(B, value)

// Generic swap via pointers
func(T) swap(a: *T, b: *T)
{
    let tmp = a[]
    a[] = b[]
    b[] = tmp
}

// Generic find in array (returns index or -1)
func(T, N: s32) indexOf(values: [N] T, target: T)->s32
{
    for var i = 0; i < N; i += 1
    {
        if values[i] == target do
            return i
    }
    return -1
}

// Generic all-equal check
func(T, N: s32) allEqual(values: [N] T, target: T)->bool
{
    for var i = 0; i < N; i += 1
    {
        if values[i] != target do
            return false
    }
    return true
}

// Generic reverse array
func(T, N: s32) reverse(values: [N] T)->[N] T
{
    var result: [N] T
    for var i = 0; i < N; i += 1 do
        result[i] = values[N - 1 - i]
    return result
}

// Generic contains
func(T, N: s32) contains(values: [N] T, target: T)->bool
{
    return indexOf(values, target) >= 0
}

// Generic count occurrences
func(T, N: s32) countOf(values: [N] T, target: T)->s32
{
    var count: s32 = 0
    for var i = 0; i < N; i += 1
    {
        if values[i] == target do
            count += 1
    }
    return count
}

// --- Tests ---

#test
{
    Swag.require(clampPositive(5) == 5)
    Swag.require(clampPositive(-3) == 0)
    Swag.require(clampPositive(0) == 0)
    Swag.require(clampPositive(-1.5) == 0.0)
    Swag.require(clampPositive(2.5) == 2.5)
}

#test
{
    let a: [3] s32 = [10, 20, 30]
    Swag.require(sum(a) == 60)

    let b: [4] f64 = [1.0, 2.0, 3.0, 4.0]
    Swag.require(sum(b) == 10.0)

    let c: [2] s64 = [100's64, 200]
    Swag.require(sum(c) == 300's64)
}

#test
{
    let a: [5] s32 = [-2, 3, -1, 0, 5]
    Swag.require(countPositive(a) == 2)

    let b: [3] f64 = [-1.0, 0.0, 1.0]
    Swag.require(countPositive(b) == 1)
}

#test
{
    Swag.require(addTwo(5) == 7)
    Swag.require(addTwo(0) == 2)
    Swag.require(addFour(10) == 14)
    Swag.require(addFour(0) == 4)
    Swag.require(addFour'(f64)(1.0) == 5.0)
}

#test
{
    Swag.require(doubleAsF64(5) == 10.0)
    Swag.require(doubleAsF64(3'u8) == 6.0)
    Swag.require(doubleAsF64(2's16) == 4.0)
}

#test
{
    Swag.require(absValue(-5) == 5)
    Swag.require(absValue(5) == 5)
    Swag.require(absValue(0) == 0)
    Swag.require(absValue(-3.5) == 3.5)
    Swag.require(absValue(2.5) == 2.5)
}

#test
{
    Swag.require(minVal(3, 7) == 3)
    Swag.require(minVal(7, 3) == 3)
    Swag.require(maxVal(3, 7) == 7)
    Swag.require(maxVal(7, 3) == 7)
    Swag.require(minVal(1.5, 2.5) == 1.5)
    Swag.require(maxVal(1.5, 2.5) == 2.5)
}

#test
{
    Swag.require(clamp(5, 0, 10) == 5)
    Swag.require(clamp(-5, 0, 10) == 0)
    Swag.require(clamp(15, 0, 10) == 10)
    Swag.require(clamp(3.5, 1.0, 5.0) == 3.5)
    Swag.require(clamp(0.5, 1.0, 5.0) == 1.0)
    Swag.require(clamp(9.0, 1.0, 5.0) == 5.0)
}

#test
{
    Swag.require(applyS32(5, &doubleS32) == 10)
    Swag.require(applyS32(-3, &negateS32) == 3)
    Swag.require(applyS32(0, &doubleS32) == 0)
    Swag.require(applyF64(2.5, &doubleF64) == 5.0)
}

#test
{
    let values: [3] s32 = [1, 2, 3]
    let doubled         = mapS32x3(values, &doubleS32)
    Swag.require(doubled[0] == 2)
    Swag.require(doubled[1] == 4)
    Swag.require(doubled[2] == 6)

    let negated = mapS32x3(values, &negateS32)
    Swag.require(negated[0] == -1)
    Swag.require(negated[1] == -2)
    Swag.require(negated[2] == -3)
}

#test
{
    let values: [4] s32 = [1, 2, 3, 4]
    Swag.require(reduceS32x4(values, 0, &addS32) == 10)
    Swag.require(reduceS32x4(values, 1, &mulS32) == 24)
}

#test
{
    Swag.require(castTo'(s32, f64)(42) == 42.0)
    Swag.require(castTo'(f64, s32)(3.7) == 3)
    Swag.require(castTo'(u8, s32)(255'u8) == 255)
    Swag.require(castTo'(bool, s32)(true) == 1)
}

#test
{
    var a: s32 = 10
    var b: s32 = 20
    swap(&a, &b)
    Swag.require(a == 20)
    Swag.require(b == 10)

    var x: f64 = 1.5
    var y: f64 = 2.5
    swap(&x, &y)
    Swag.require(x == 2.5)
    Swag.require(y == 1.5)
}

#test
{
    let arr: [5] s32 = [10, 20, 30, 40, 50]
    Swag.require(indexOf(arr, 30) == 2)
    Swag.require(indexOf(arr, 10) == 0)
    Swag.require(indexOf(arr, 50) == 4)
    Swag.require(indexOf(arr, 99) == -1)
}

#test
{
    let ones: [3] s32 = [1, 1, 1]
    Swag.require(allEqual(ones, 1) == true)
    Swag.require(allEqual(ones, 2) == false)

    let mixed: [3] s32 = [1, 2, 1]
    Swag.require(allEqual(mixed, 1) == false)
}

#test
{
    let arr: [4] s32 = [10, 20, 30, 40]
    let rev = reverse(arr)
    Swag.require(rev[0] == 40)
    Swag.require(rev[1] == 30)
    Swag.require(rev[2] == 20)
    Swag.require(rev[3] == 10)

    let farr: [3] f64 = [1.0, 2.0, 3.0]
    let frev = reverse(farr)
    Swag.require(frev[0] == 3.0)
    Swag.require(frev[1] == 2.0)
    Swag.require(frev[2] == 1.0)
}

#test
{
    let arr: [5] s32 = [10, 20, 30, 20, 50]
    Swag.require(contains(arr, 30) == true)
    Swag.require(contains(arr, 99) == false)
    Swag.require(countOf(arr, 20) == 2)
    Swag.require(countOf(arr, 10) == 1)
    Swag.require(countOf(arr, 99) == 0)
}

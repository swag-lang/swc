#global fileprivate

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
func(T) addOne(value: T)->T => value + 1
func(T) addTwo(value: T)->T => addOne(addOne(value))
func(T) addFour(value: T)->T => addTwo(addTwo(value))

// Generic calling another generic with different type
func(T) toF64(value: T)->f64 => cast(f64) value
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
    var result: [3] s32 = undefined
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
func(A, B) castTo(value: A)->B => cast(B) value

// Generic swap via pointers
func(T) swap(a: *T, b: *T)
{
    let tmp = dref a
    dref a = dref b
    dref b = tmp
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
    var result: [N] T = undefined
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
    @assert(clampPositive(5) == 5)
    @assert(clampPositive(-3) == 0)
    @assert(clampPositive(0) == 0)
    @assert(clampPositive(-1.5) == 0.0)
    @assert(clampPositive(2.5) == 2.5)
}

#test
{
    let a: [3] s32 = [10, 20, 30]
    @assert(sum(a) == 60)

    let b: [4] f64 = [1.0, 2.0, 3.0, 4.0]
    @assert(sum(b) == 10.0)

    let c: [2] s64 = [100's64, 200]
    @assert(sum(c) == 300's64)
}

#test
{
    let a: [5] s32 = [-2, 3, -1, 0, 5]
    @assert(countPositive(a) == 2)

    let b: [3] f64 = [-1.0, 0.0, 1.0]
    @assert(countPositive(b) == 1)
}

#test
{
    @assert(addTwo(5) == 7)
    @assert(addTwo(0) == 2)
    @assert(addFour(10) == 14)
    @assert(addFour(0) == 4)
    @assert(addFour'(f64)(1.0) == 5.0)
}

#test
{
    @assert(doubleAsF64(5) == 10.0)
    @assert(doubleAsF64(3'u8) == 6.0)
    @assert(doubleAsF64(2's16) == 4.0)
}

#test
{
    @assert(absValue(-5) == 5)
    @assert(absValue(5) == 5)
    @assert(absValue(0) == 0)
    @assert(absValue(-3.5) == 3.5)
    @assert(absValue(2.5) == 2.5)
}

#test
{
    @assert(minVal(3, 7) == 3)
    @assert(minVal(7, 3) == 3)
    @assert(maxVal(3, 7) == 7)
    @assert(maxVal(7, 3) == 7)
    @assert(minVal(1.5, 2.5) == 1.5)
    @assert(maxVal(1.5, 2.5) == 2.5)
}

#test
{
    @assert(clamp(5, 0, 10) == 5)
    @assert(clamp(-5, 0, 10) == 0)
    @assert(clamp(15, 0, 10) == 10)
    @assert(clamp(3.5, 1.0, 5.0) == 3.5)
    @assert(clamp(0.5, 1.0, 5.0) == 1.0)
    @assert(clamp(9.0, 1.0, 5.0) == 5.0)
}

#test
{
    @assert(applyS32(5, &doubleS32) == 10)
    @assert(applyS32(-3, &negateS32) == 3)
    @assert(applyS32(0, &doubleS32) == 0)
    @assert(applyF64(2.5, &doubleF64) == 5.0)
}

#test
{
    let values: [3] s32 = [1, 2, 3]
    let doubled = mapS32x3(values, &doubleS32)
    @assert(doubled[0] == 2)
    @assert(doubled[1] == 4)
    @assert(doubled[2] == 6)

    let negated = mapS32x3(values, &negateS32)
    @assert(negated[0] == -1)
    @assert(negated[1] == -2)
    @assert(negated[2] == -3)
}

#test
{
    let values: [4] s32 = [1, 2, 3, 4]
    @assert(reduceS32x4(values, 0, &addS32) == 10)
    @assert(reduceS32x4(values, 1, &mulS32) == 24)
}

#test
{
    @assert(castTo'(s32, f64)(42) == 42.0)
    @assert(castTo'(f64, s32)(3.7) == 3)
    @assert(castTo'(u8, s32)(255'u8) == 255)
    @assert(castTo'(bool, s32)(true) == 1)
}

#test
{
    var a: s32 = 10
    var b: s32 = 20
    swap(&a, &b)
    @assert(a == 20)
    @assert(b == 10)

    var x: f64 = 1.5
    var y: f64 = 2.5
    swap(&x, &y)
    @assert(x == 2.5)
    @assert(y == 1.5)
}

#test
{
    let arr: [5] s32 = [10, 20, 30, 40, 50]
    @assert(indexOf(arr, 30) == 2)
    @assert(indexOf(arr, 10) == 0)
    @assert(indexOf(arr, 50) == 4)
    @assert(indexOf(arr, 99) == -1)
}

#test
{
    let ones: [3] s32 = [1, 1, 1]
    @assert(allEqual(ones, 1) == true)
    @assert(allEqual(ones, 2) == false)

    let mixed: [3] s32 = [1, 2, 1]
    @assert(allEqual(mixed, 1) == false)
}

#test
{
    let arr: [4] s32 = [10, 20, 30, 40]
    let rev = reverse(arr)
    @assert(rev[0] == 40)
    @assert(rev[1] == 30)
    @assert(rev[2] == 20)
    @assert(rev[3] == 10)

    let farr: [3] f64 = [1.0, 2.0, 3.0]
    let frev = reverse(farr)
    @assert(frev[0] == 3.0)
    @assert(frev[1] == 2.0)
    @assert(frev[2] == 1.0)
}

#test
{
    let arr: [5] s32 = [10, 20, 30, 20, 50]
    @assert(contains(arr, 30) == true)
    @assert(contains(arr, 99) == false)
    @assert(countOf(arr, 20) == 2)
    @assert(countOf(arr, 10) == 1)
    @assert(countOf(arr, 99) == 0)
}

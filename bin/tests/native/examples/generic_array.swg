#global fileprivate

// Real-life example: a generic dynamic array backed by @alloc, @free, @realloc.

const DefaultCapacity = 4'u64

struct(T) DynArray
{
    data:     [*] T
    count:    u64
    capacity: u64
}

func(T) create()->DynArray'T
{
    var result: DynArray'T
    result.capacity = DefaultCapacity
    result.data = cast([*] T) @alloc(DefaultCapacity * #sizeof(T))
    return result
}

func(T) destroy(arr: *DynArray'T)
{
    if arr.data do
        @free(arr.data)
    arr.data = null
    arr.count = 0
    arr.capacity = 0
}

func(T) push(arr: *DynArray'T, value: T)
{
    if arr.count == arr.capacity
    {
        let newCapacity = arr.capacity * 2
        arr.data = cast([*] T) @realloc(arr.data, newCapacity * #sizeof(T))
        arr.capacity = newCapacity
    }

    arr.data[arr.count] = value
    arr.count += 1
}

func(T) pop(arr: *DynArray'T)->T
{
    @assert(arr.count > 0)
    arr.count -= 1
    return arr.data[arr.count]
}

func(T) get(arr: *DynArray'T, index: u64)->T
{
    @assert(index < arr.count)
    return arr.data[index]
}

func(T) set(arr: *DynArray'T, index: u64, value: T)
{
    @assert(index < arr.count)
    arr.data[index] = value
}

func(T) clear(arr: *DynArray'T)
{
    arr.count = 0
}

func(T) last(arr: *DynArray'T)->T
{
    @assert(arr.count > 0)
    return arr.data[arr.count - 1]
}

func(T) contains(arr: *DynArray'T, value: T)->bool
{
    for i in arr.count
    {
        if arr.data[i] == value do
            return true
    }

    return false
}

func(T) removeAt(arr: *DynArray'T, index: u64)
{
    @assert(index < arr.count)
    var i = index
    while i + 1 < arr.count
    {
        arr.data[i] = arr.data[i + 1]
        i += 1
    }

    arr.count -= 1
}

func(T) insertAt(arr: *DynArray'T, index: u64, value: T)
{
    @assert(index <= arr.count)
    if arr.count == arr.capacity
    {
        let newCapacity = arr.capacity * 2
        arr.data = cast([*] T) @realloc(arr.data, newCapacity * #sizeof(T))
        arr.capacity = newCapacity
    }

    var i = arr.count
    while i > index
    {
        arr.data[i] = arr.data[i - 1]
        i -= 1
    }

    arr.data[index] = value
    arr.count += 1
}

func(T) reverse(arr: *DynArray'T)
{
    if arr.count <= 1 do
        return
    var lo: u64 = 0
    var hi = arr.count - 1
    while lo < hi
    {
        let tmp = arr.data[lo]
        arr.data[lo] = arr.data[hi]
        arr.data[hi] = tmp
        lo += 1
        hi -= 1
    }
}

// ---------------------------------------------------------------------------
// Test: u32 - basic push, get, pop, grow
// ---------------------------------------------------------------------------

#test
{
    var arr = create'u32()
    defer destroy'u32(&arr)

    @assert(arr.count == 0)
    @assert(arr.capacity == DefaultCapacity)

    push'u32(&arr, 10)
    push'u32(&arr, 20)
    push'u32(&arr, 30)
    @assert(arr.count == 3)
    @assert(get'u32(&arr, 0) == 10)
    @assert(get'u32(&arr, 1) == 20)
    @assert(get'u32(&arr, 2) == 30)
    @assert(last'u32(&arr) == 30)

    let popped = pop'u32(&arr)
    @assert(popped == 30)
    @assert(arr.count == 2)

    // Force a grow beyond initial capacity
    push'u32(&arr, 40)
    push'u32(&arr, 50)
    push'u32(&arr, 60)
    @assert(arr.count == 5)
    @assert(arr.capacity >= 5)
    @assert(get'u32(&arr, 4) == 60)
}

// ---------------------------------------------------------------------------
// Test: s32 - negative values, set, contains, removeAt
// ---------------------------------------------------------------------------

#test
{
    var arr = create's32()
    defer destroy's32(&arr)

    push's32(&arr, -5)
    push's32(&arr, 0)
    push's32(&arr, 7)
    push's32(&arr, -3)

    @assert(arr.count == 4)
    @assert(contains's32(&arr, -5))
    @assert(contains's32(&arr, 0))
    @assert(contains's32(&arr, 7))
    @assert(!contains's32(&arr, 99))

    set's32(&arr, 1, 42)
    @assert(get's32(&arr, 1) == 42)
    @assert(!contains's32(&arr, 0))

    removeAt's32(&arr, 0)
    @assert(arr.count == 3)
    @assert(get's32(&arr, 0) == 42)
    @assert(get's32(&arr, 1) == 7)
    @assert(get's32(&arr, 2) == -3)
}

// ---------------------------------------------------------------------------
// Test: f64 - floating point values
// ---------------------------------------------------------------------------

#test
{
    var arr = create'f64()
    defer destroy'f64(&arr)

    push'f64(&arr, 1.5)
    push'f64(&arr, 2.75)
    push'f64(&arr, 3.125)

    @assert(arr.count == 3)
    @assert(get'f64(&arr, 0) == 1.5)
    @assert(get'f64(&arr, 1) == 2.75)
    @assert(get'f64(&arr, 2) == 3.125)

    let sum = get'f64(&arr, 0) + get'f64(&arr, 1) + get'f64(&arr, 2)
    @assert(sum == 7.375)
}

// ---------------------------------------------------------------------------
// Test: u8 - small type, insertAt, reverse
// ---------------------------------------------------------------------------

#test
{
    var arr = create'u8()
    defer destroy'u8(&arr)

    push'u8(&arr, 'A')
    push'u8(&arr, 'B')
    push'u8(&arr, 'D')

    insertAt'u8(&arr, 2, 'C')
    @assert(arr.count == 4)
    @assert(get'u8(&arr, 0) == 'A')
    @assert(get'u8(&arr, 1) == 'B')
    @assert(get'u8(&arr, 2) == 'C')
    @assert(get'u8(&arr, 3) == 'D')

    reverse'u8(&arr)
    @assert(get'u8(&arr, 0) == 'D')
    @assert(get'u8(&arr, 1) == 'C')
    @assert(get'u8(&arr, 2) == 'B')
    @assert(get'u8(&arr, 3) == 'A')
}

// ---------------------------------------------------------------------------
// Test: bool - clear, re-use after clear
// ---------------------------------------------------------------------------

#test
{
    var arr = create'bool()
    defer destroy'bool(&arr)

    push'bool(&arr, true)
    push'bool(&arr, false)
    push'bool(&arr, true)
    @assert(arr.count == 3)
    @assert(get'bool(&arr, 0) == true)
    @assert(get'bool(&arr, 1) == false)

    clear'bool(&arr)
    @assert(arr.count == 0)

    push'bool(&arr, false)
    @assert(arr.count == 1)
    @assert(get'bool(&arr, 0) == false)
}

// ---------------------------------------------------------------------------
// Test: u64 - large grow, many elements
// ---------------------------------------------------------------------------

#test
{
    var arr = create'u64()
    defer destroy'u64(&arr)

    for i in 100'u64 do
        push'u64(&arr, i * i)

    @assert(arr.count == 100)
    @assert(arr.capacity >= 100)
    @assert(get'u64(&arr, 0) == 0)
    @assert(get'u64(&arr, 1) == 1)
    @assert(get'u64(&arr, 10) == 100)
    @assert(get'u64(&arr, 99) == 9801)

    // Pop half
    for 50 do
        pop'u64(&arr)
    @assert(arr.count == 50)
    @assert(last'u64(&arr) == 49 * 49)
}

// ---------------------------------------------------------------------------
// Test: s64 - insertAt at boundaries
// ---------------------------------------------------------------------------

#test
{
    var arr = create's64()
    defer destroy's64(&arr)

    // Insert at index 0 on empty array
    insertAt's64(&arr, 0, 100)
    @assert(arr.count == 1)
    @assert(get's64(&arr, 0) == 100)

    // Insert at end
    insertAt's64(&arr, 1, 300)
    @assert(arr.count == 2)
    @assert(get's64(&arr, 1) == 300)

    // Insert in the middle
    insertAt's64(&arr, 1, 200)
    @assert(arr.count == 3)
    @assert(get's64(&arr, 0) == 100)
    @assert(get's64(&arr, 1) == 200)
    @assert(get's64(&arr, 2) == 300)
}

// ---------------------------------------------------------------------------
// Test: f32 - reverse on odd and even counts
// ---------------------------------------------------------------------------

#test
{
    var arr = create'f32()
    defer destroy'f32(&arr)

    // Odd count
    push'f32(&arr, 1.0)
    push'f32(&arr, 2.0)
    push'f32(&arr, 3.0)
    reverse'f32(&arr)
    @assert(get'f32(&arr, 0) == 3.0)
    @assert(get'f32(&arr, 1) == 2.0)
    @assert(get'f32(&arr, 2) == 1.0)

    clear'f32(&arr)

    // Even count
    push'f32(&arr, 10.0)
    push'f32(&arr, 20.0)
    push'f32(&arr, 30.0)
    push'f32(&arr, 40.0)
    reverse'f32(&arr)
    @assert(get'f32(&arr, 0) == 40.0)
    @assert(get'f32(&arr, 1) == 30.0)
    @assert(get'f32(&arr, 2) == 20.0)
    @assert(get'f32(&arr, 3) == 10.0)
}

// ---------------------------------------------------------------------------
// Test: u16 - removeAt edge cases
// ---------------------------------------------------------------------------

#test
{
    var arr = create'u16()
    defer destroy'u16(&arr)

    push'u16(&arr, 100)
    push'u16(&arr, 200)
    push'u16(&arr, 300)
    push'u16(&arr, 400)
    push'u16(&arr, 500)

    // Remove last element
    removeAt'u16(&arr, 4)
    @assert(arr.count == 4)
    @assert(last'u16(&arr) == 400)

    // Remove first element
    removeAt'u16(&arr, 0)
    @assert(arr.count == 3)
    @assert(get'u16(&arr, 0) == 200)

    // Remove middle element
    removeAt'u16(&arr, 1)
    @assert(arr.count == 2)
    @assert(get'u16(&arr, 0) == 200)
    @assert(get'u16(&arr, 1) == 400)
}

// ---------------------------------------------------------------------------
// Test: struct type - DynArray of a custom struct
// ---------------------------------------------------------------------------

struct Point
{
    x: s32
    y: s32
}

#test
{
    var arr = create'Point()
    defer destroy'Point(&arr)

    push'Point(&arr, {x: 1, y: 2})
    push'Point(&arr, {x: 3, y: 4})
    push'Point(&arr, {x: 5, y: 6})

    @assert(arr.count == 3)
    @assert(get'Point(&arr, 0).x == 1)
    @assert(get'Point(&arr, 0).y == 2)
    @assert(get'Point(&arr, 1).x == 3)
    @assert(get'Point(&arr, 2).y == 6)

    set'Point(&arr, 1, {x: 10, y: 20})
    @assert(get'Point(&arr, 1).x == 10)
    @assert(get'Point(&arr, 1).y == 20)

    reverse'Point(&arr)
    @assert(get'Point(&arr, 0).x == 5)
    @assert(get'Point(&arr, 2).x == 1)
}

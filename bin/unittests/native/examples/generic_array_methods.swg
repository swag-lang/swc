#global fileprivate

// Real-life example: a generic dynamic array backed by @alloc, @free, @realloc.
// Same as dynamic_generic_array.swg but using methods instead of global functions.

const DefaultCapacity = 4'u64

struct(T) DynArray
{
    data:     [*] T
    count:    u64
    capacity: u64
}

impl DynArray
{
    func(T) create()->DynArray'T
    {
        var result: DynArray'T
        result.capacity = DefaultCapacity
        result.data = cast([*] T) @alloc(DefaultCapacity * #sizeof(T))
        return result
    }

    mtd destroy()
    {
        if .data do
            @free(.data)
        .data = null
        .count = 0
        .capacity = 0
    }

    func push(me, value: T)
    {
        if me.count == me.capacity
        {
            let newCapacity = me.capacity * 2
            me.data = cast([*] T) @realloc(me.data, newCapacity * #sizeof(T))
            me.capacity = newCapacity
        }

        me.data[me.count] = value
        me.count += 1
    }

    mtd pop()->T
    {
        @assert(.count > 0)
        .count -= 1
        return .data[.count]
    }

    func get(me, index: u64)->T
    {
        @assert(index < me.count)
        return me.data[index]
    }

    func set(me, index: u64, value: T)
    {
        @assert(index < me.count)
        me.data[index] = value
    }

    mtd clear()
    {
        .count = 0
    }

    mtd last()->T
    {
        @assert(.count > 0)
        return .data[.count - 1]
    }

    func contains(me, value: T)->bool
    {
        for i in me.count
        {
            if me.data[i] == value do
                return true
        }

        return false
    }

    func removeAt(me, index: u64)
    {
        @assert(index < me.count)
        var i = index
        while i + 1 < me.count
        {
            me.data[i] = me.data[i + 1]
            i += 1
        }

        me.count -= 1
    }

    func insertAt(me, index: u64, value: T)
    {
        @assert(index <= me.count)
        if me.count == me.capacity
        {
            let newCapacity = me.capacity * 2
            me.data = cast([*] T) @realloc(me.data, newCapacity * #sizeof(T))
            me.capacity = newCapacity
        }

        var i = me.count
        while i > index
        {
            me.data[i] = me.data[i - 1]
            i -= 1
        }

        me.data[index] = value
        me.count += 1
    }

    mtd reverse()
    {
        if .count <= 1 do
            return
        var lo: u64 = 0
        var hi = .count - 1
        while lo < hi
        {
            let tmp = .data[lo]
            .data[lo] = .data[hi]
            .data[hi] = tmp
            lo += 1
            hi -= 1
        }
    }
}

// ---------------------------------------------------------------------------
// Test: u32 - basic push, get, pop, grow
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'u32.create()
    defer arr.destroy()

    @assert(arr.count == 0)
    @assert(arr.capacity == DefaultCapacity)

    arr.push(10)
    arr.push(20)
    arr.push(30)
    @assert(arr.count == 3)
    @assert(arr.get(0) == 10)
    @assert(arr.get(1) == 20)
    @assert(arr.get(2) == 30)
    @assert(arr.last() == 30)

    let popped = arr.pop()
    @assert(popped == 30)
    @assert(arr.count == 2)

    // Force a grow beyond initial capacity
    arr.push(40)
    arr.push(50)
    arr.push(60)
    @assert(arr.count == 5)
    @assert(arr.capacity >= 5)
    @assert(arr.get(4) == 60)
}

// ---------------------------------------------------------------------------
// Test: s32 - negative values, set, contains, removeAt
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray's32.create()
    defer arr.destroy()

    arr.push(-5)
    arr.push(0)
    arr.push(7)
    arr.push(-3)

    @assert(arr.count == 4)
    @assert(arr.contains(-5))
    @assert(arr.contains(0))
    @assert(arr.contains(7))
    @assert(!arr.contains(99))

    arr.set(1, 42)
    @assert(arr.get(1) == 42)
    @assert(!arr.contains(0))

    arr.removeAt(0)
    @assert(arr.count == 3)
    @assert(arr.get(0) == 42)
    @assert(arr.get(1) == 7)
    @assert(arr.get(2) == -3)
}

// ---------------------------------------------------------------------------
// Test: f64 - floating point values
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'f64.create()
    defer arr.destroy()

    arr.push(1.5)
    arr.push(2.75)
    arr.push(3.125)

    @assert(arr.count == 3)
    @assert(arr.get(0) == 1.5)
    @assert(arr.get(1) == 2.75)
    @assert(arr.get(2) == 3.125)

    let sum = arr.get(0) + arr.get(1) + arr.get(2)
    @assert(sum == 7.375)
}

// ---------------------------------------------------------------------------
// Test: u8 - small type, insertAt, reverse
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'u8.create()
    defer arr.destroy()

    arr.push('A')
    arr.push('B')
    arr.push('D')

    arr.insertAt(2, 'C')
    @assert(arr.count == 4)
    @assert(arr.get(0) == 'A')
    @assert(arr.get(1) == 'B')
    @assert(arr.get(2) == 'C')
    @assert(arr.get(3) == 'D')

    arr.reverse()
    @assert(arr.get(0) == 'D')
    @assert(arr.get(1) == 'C')
    @assert(arr.get(2) == 'B')
    @assert(arr.get(3) == 'A')
}

// ---------------------------------------------------------------------------
// Test: bool - clear, re-use after clear
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'bool.create()
    defer arr.destroy()

    arr.push(true)
    arr.push(false)
    arr.push(true)
    @assert(arr.count == 3)
    @assert(arr.get(0) == true)
    @assert(arr.get(1) == false)

    arr.clear()
    @assert(arr.count == 0)

    arr.push(false)
    @assert(arr.count == 1)
    @assert(arr.get(0) == false)
}

// ---------------------------------------------------------------------------
// Test: u64 - large grow, many elements
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'u64.create()
    defer arr.destroy()

    for i in 100'u64 do
        arr.push(i * i)

    @assert(arr.count == 100)
    @assert(arr.capacity >= 100)
    @assert(arr.get(0) == 0)
    @assert(arr.get(1) == 1)
    @assert(arr.get(10) == 100)
    @assert(arr.get(99) == 9801)

    // Pop half
    for 50 do
        arr.pop()
    @assert(arr.count == 50)
    @assert(arr.last() == 49 * 49)
}

// ---------------------------------------------------------------------------
// Test: s64 - insertAt at boundaries
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray's64.create()
    defer arr.destroy()

    // Insert at index 0 on empty array
    arr.insertAt(0, 100)
    @assert(arr.count == 1)
    @assert(arr.get(0) == 100)

    // Insert at end
    arr.insertAt(1, 300)
    @assert(arr.count == 2)
    @assert(arr.get(1) == 300)

    // Insert in the middle
    arr.insertAt(1, 200)
    @assert(arr.count == 3)
    @assert(arr.get(0) == 100)
    @assert(arr.get(1) == 200)
    @assert(arr.get(2) == 300)
}

// ---------------------------------------------------------------------------
// Test: f32 - reverse on odd and even counts
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'f32.create()
    defer arr.destroy()

    // Odd count
    arr.push(1.0)
    arr.push(2.0)
    arr.push(3.0)
    arr.reverse()
    @assert(arr.get(0) == 3.0)
    @assert(arr.get(1) == 2.0)
    @assert(arr.get(2) == 1.0)

    arr.clear()

    // Even count
    arr.push(10.0)
    arr.push(20.0)
    arr.push(30.0)
    arr.push(40.0)
    arr.reverse()
    @assert(arr.get(0) == 40.0)
    @assert(arr.get(1) == 30.0)
    @assert(arr.get(2) == 20.0)
    @assert(arr.get(3) == 10.0)
}

// ---------------------------------------------------------------------------
// Test: u16 - removeAt edge cases
// ---------------------------------------------------------------------------

#test
{
    var arr = DynArray'u16.create()
    defer arr.destroy()

    arr.push(100)
    arr.push(200)
    arr.push(300)
    arr.push(400)
    arr.push(500)

    // Remove last element
    arr.removeAt(4)
    @assert(arr.count == 4)
    @assert(arr.last() == 400)

    // Remove first element
    arr.removeAt(0)
    @assert(arr.count == 3)
    @assert(arr.get(0) == 200)

    // Remove middle element
    arr.removeAt(1)
    @assert(arr.count == 2)
    @assert(arr.get(0) == 200)
    @assert(arr.get(1) == 400)
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
    var arr = DynArray'Point.create()
    defer arr.destroy()

    arr.push({x: 1, y: 2})
    arr.push({x: 3, y: 4})
    arr.push({x: 5, y: 6})

    @assert(arr.count == 3)
    @assert(arr.get(0).x == 1)
    @assert(arr.get(0).y == 2)
    @assert(arr.get(1).x == 3)
    @assert(arr.get(2).y == 6)

    arr.set(1, {x: 10, y: 20})
    @assert(arr.get(1).x == 10)
    @assert(arr.get(1).y == 20)

    arr.reverse()
    @assert(arr.get(0).x == 5)
    @assert(arr.get(2).x == 1)
}

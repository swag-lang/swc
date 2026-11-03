#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertHashSetKeysAreReadOnly(values: *HashSet's32)
{
    for &key in values[]
    {
        #assert(#typeof(key) == const *s32)
    }

    for &key in values[].reversed()
    {
        #assert(#typeof(key) == const *s32)
    }
}

struct RejectHashSetGrowthAllocator {}

impl Swag.IAllocator for RejectHashSetGrowthAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(_: *Swag.AllocatorRequest) {}
}

func assertStringSetHas(values: HashSet'String, expected: string)->bool
{
    for value in values
    {
        if value.toString() == expected do
            return true
    }

    return false
}

func assertReverseIntSetIteration(values: HashSet's32)->bool
{
    var forward: Array's32
    for value in values do
        forward.add(value)

    var reverse: Array's32
    for value in values.reversed() do
        reverse.add(value)

    if forward.count != reverse.count do
        return false

    for i in forward.count
    {
        if forward[i] != reverse[reverse.count - i - 1] do
            return false
    }

    return true
}

#test
{
    var values: HashSet's32
    Swag.require(values.isEmpty())
    Swag.require(not values.contains(1))

    values.add(1)
    values.add(3)
    values.add(1)

    assertHashSetKeysAreReadOnly(&values)

    Swag.require(values.count == 2)
    Swag.require(values.contains(1))
    Swag.require(values.contains(3))

    var sum = 0
    for value in values do
        sum += value
    Swag.require(sum == 4)
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)
    values.add(4)

    Swag.require(assertReverseIntSetIteration(values))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)

    values.remove(2)
    Swag.require(not values.contains(2))
    Swag.require(values.count == 2)

    values.add(2)
    Swag.require(values.contains(2))
    Swag.require(values.count == 3)

    values.clear()
    Swag.require(values.isEmpty())
    Swag.require(not values.contains(1))
    Swag.require(not values.contains(2))
    Swag.require(not values.contains(3))
}

#test
{
    var moved: String = "beta"

    var values: HashSet'String
    values.add("alpha")
    values.add(#move moved)

    Swag.require(values.count == 2)
    Swag.require(values.contains("alpha"))
    Swag.require(values.contains("beta"))
    Swag.require(assertStringSetHas(values, "alpha"))
    Swag.require(assertStringSetHas(values, "beta"))
}

#test
{
    var original: HashSet'String
    original.add("alpha")
    original.add("beta")
    original.remove("alpha")

    var copy = original
    copy.add("gamma")
    copy.add("alpha")

    Swag.require(not assertStringSetHas(original, "alpha"))
    Swag.require(assertStringSetHas(original, "beta"))

    Swag.require(assertStringSetHas(copy, "alpha"))
    Swag.require(assertStringSetHas(copy, "beta"))
    Swag.require(assertStringSetHas(copy, "gamma"))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)

    let seed: [1] s32 = [3]
    values = seed

    Swag.require(values.count == 1)
    Swag.require(not values.contains(1))
    Swag.require(not values.contains(2))
    Swag.require(values.contains(3))
}

#test
{
    var values: HashSet's32
    values.reserve(33)

    values.add(10)
    values.add(42)
    values.add(74)

    Swag.require(values.capacity >= 33)
    Swag.require(values.contains(10))
    Swag.require(values.contains(42))
    Swag.require(values.contains(74))
}

#test
{
    var values: HashSet's32
    let result = Swag.catchPanic(func|&values|() { values.reserve(Swag.U64.Max) })
    Swag.require(result.raised)
    Swag.require(result.message() == "HashSet capacity exceeds addressable memory")
}

#test
{
    var reject: RejectHashSetGrowthAllocator
    var values: HashSet's32
    values.add(42)

    let oldCapacity  = values.capacity
    let oldAllocator = values.allocator
    values.allocator = &reject

    let failed = Swag.catchPanic(func|&values, oldCapacity|() { values.reserve(oldCapacity + 1) })
    values.allocator = oldAllocator

    Swag.require(failed.raised)
    Swag.require(values.capacity == oldCapacity and values.count == 1 and values.contains(42))
}

#test
{
    var reject: RejectHashSetGrowthAllocator
    var values: HashSet's32
    for value in 16 do
        values.add(cast(s32, value))

    let oldCapacity  = values.capacity
    let oldAllocator = values.allocator
    values.allocator = &reject

    let duplicateFailed = Swag.catchPanic(func|&values|() { discard values.add(7) })
    var toggleResult    = true
    let toggleFailed    = Swag.catchPanic(func|&values, &toggleResult|() { toggleResult = values.toggle(7) })
    values.allocator = oldAllocator

    Swag.require(not duplicateFailed.raised and not toggleFailed.raised and not toggleResult)
    Swag.require(values.capacity == oldCapacity and values.count == 15 and not values.contains(7))
}

#test
{
    var values: HashSet's32

    Swag.require(values.toggle(10))
    Swag.require(values.contains(10))
    Swag.require(values.count == 1)

    Swag.require(not values.toggle(10))
    Swag.require(not values.contains(10))
    Swag.require(values.isEmpty())

    values.add(42)
    Swag.require(not values.toggle(42))
    Swag.require(not values.contains(42))
    Swag.require(values.isEmpty())
}

// A key read from the set itself can be added back while the set grows.
#test
{
    var s: HashSet'String
    discard s.add("a key long enough to live outside the inline storage")
    for i in 100
    {
        for k in s
        {
            discard s.add(k)
            break
        }

        discard s.add(Format.toString("key %", i))
    }

    Swag.require(s.count == 101 and s.contains("a key long enough to live outside the inline storage"))
}

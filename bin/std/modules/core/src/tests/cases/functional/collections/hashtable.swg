#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertHashTableBorrowTypes(table: *HashTable'(s32, s32))
{
    for &key, value in table[]
    {
        #assert(#typeof(key) == const *s32)
        #assert(#typeof(value) == *s32)
    }

    for &key, value in table[].reversed()
    {
        #assert(#typeof(key) == const *s32)
        #assert(#typeof(value) == *s32)
    }
}

struct RejectHashTableGrowthAllocator {}

impl Swag.IAllocator for RejectHashTableGrowthAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(_: *Swag.AllocatorRequest) {}
}

func assertReverseIntTableIteration(table: HashTable'(s32, s32))->bool
{
    var forwardKeys:   Array's32
    var forwardValues: Array's32
    for key, value in table
    {
        forwardKeys.add(key)
        forwardValues.add(value)
    }

    var reverseKeys:   Array's32
    var reverseValues: Array's32
    for key, value in table.reversed()
    {
        reverseKeys.add(key)
        reverseValues.add(value)
    }

    if forwardKeys.count != reverseKeys.count do
        return false

    for i in forwardKeys.count
    {
        let reverseIndex = reverseKeys.count - i - 1
        if forwardKeys[i] != reverseKeys[reverseIndex] do
            return false
        if forwardValues[i] != reverseValues[reverseIndex] do
            return false
    }

    return true
}

#test
{
    var table: HashTable'(s32, s32)
    Swag.require(table.isEmpty())
    Swag.require(not table.contains(1))
    Swag.require(table.tryFind(1) == null)

    table.add(1, 10)
    table[1] = 11
    table[3] = 30

    assertHashTableBorrowTypes(&table)

    Swag.require(table.count == 2)
    Swag.require(table.contains(1))
    Swag.require(table.contains(3))
    Swag.require(table.getOrDefault(9, 99) == 99)
    Swag.require(table[1] == 11)
    Swag.require(table[3] == 30)
}

#test
{
    var table: HashTable'(s32, s32)

    var movedValue: s32 = 20
    table.add(2, #move movedValue)

    let slot4 = table.findOrAdd(4)
    slot4.value = 40

    let entryTwo = table.find(2)
    entryTwo.value += 2

    Swag.require(table.count == 2)
    Swag.require(table[2] == 22)
    Swag.require(table[4] == 40)
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)
    table.add(4, 40)

    var sumKeys   = 0
    var sumValues = 0
    for key, value in table
    {
        #assert(#typeof(key) == s32)
        #assert(#typeof(value) == s32)
        sumKeys   += key
        sumValues += value
    }

    Swag.require(sumKeys == 10)
    Swag.require(sumValues == 103)
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)
    table.add(4, 40)

    Swag.require(assertReverseIntTableIteration(table))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)

    table.remove(2)
    Swag.require(not table.contains(2))
    Swag.require(table.count == 2)

    table.add(2, 200)
    table.add(2, 999, false)
    Swag.require(table.count == 3)
    Swag.require(table[2] == 200)

    table.clear()
    Swag.require(table.isEmpty())
    Swag.require(not table.contains(1))
    Swag.require(not table.contains(2))
}

func assertTableStringValue(table: HashTable'(string, String), key: string, expected: string)->bool
{
    let entry = table.tryFind(key)
    return entry != null and entry.value == expected and entry.value.count == expected.count
}

#test
{
    var original: HashTable'(string, s32)
    original.add("alpha", 1)

    let entry = unwrap original.tryFind("alpha")
    Swag.require(entry.value == 1)
}

#test
{
    var original: HashTable'(s32, String)
    original.add(1, "one")
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")

    Swag.require(assertTableStringValue(original, "alpha", "one"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    Swag.require(assertTableStringValue(original, "alpha", "one"))
    Swag.require(assertTableStringValue(original, "beta", "two"))
    Swag.require(original.tryFind("gamma") == null)
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    var copy = original
    copy["alpha"] = "uno"
    copy.findOrAdd("gamma").value = "three"

    Swag.require(assertTableStringValue(original, "alpha", "one"))
    Swag.require(assertTableStringValue(original, "beta", "two"))
    Swag.require(original.tryFind("gamma") == null)

    Swag.require(assertTableStringValue(copy, "alpha", "uno"))
    Swag.require(assertTableStringValue(copy, "beta", "two"))
    Swag.require(assertTableStringValue(copy, "gamma", "three"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")
    original.remove("alpha")

    var copy = original
    copy.add("alpha", "uno")

    Swag.require(original.tryFind("alpha") == null)
    Swag.require(assertTableStringValue(original, "beta", "two"))

    Swag.require(assertTableStringValue(copy, "alpha", "uno"))
    Swag.require(assertTableStringValue(copy, "beta", "two"))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 10)
    table.add(2, 20)

    table.opSet([struct { k: s32, v: s32 }{k: 3, v: 30}])

    Swag.require(table.count == 1)
    Swag.require(not table.contains(1))
    Swag.require(not table.contains(2))
    Swag.require(table.contains(3))
    Swag.require(table[3] == 30)
}

#test
{
    var table: HashTable'(s32, s32)
    table.reserve(33)

    table.add(10, 100)
    table.add(42, 420)
    table.add(74, 740)

    Swag.require(table.capacity >= 33)
    Swag.require(table.contains(10))
    Swag.require(table.contains(42))
    Swag.require(table.contains(74))
    Swag.require(table[10] == 100)
    Swag.require(table[42] == 420)
    Swag.require(table[74] == 740)
}

#test
{
    var table: HashTable'(s32, s32)
    let result = Swag.catchPanic(func|&table|() { table.reserve(Swag.U64.Max) })
    Swag.require(result.raised)
    Swag.require(result.message() == "HashTable capacity exceeds addressable memory")
}

#test
{
    var reject: RejectHashTableGrowthAllocator
    var table:  HashTable'(s32, s32)
    table.add(42, 420)

    let oldCapacity  = table.capacity
    let oldAllocator = table.allocator
    table.allocator = &reject

    let failed = Swag.catchPanic(func|&table, oldCapacity|() { table.reserve(oldCapacity + 1) })
    table.allocator = oldAllocator

    Swag.require(failed.raised)
    Swag.require(table.capacity == oldCapacity and table.count == 1 and table[42] == 420)
}

#test
{
    var reject: RejectHashTableGrowthAllocator
    var table:  HashTable'(s32, s32)
    for key in 16 do
        table.add(cast(s32, key), cast(s32, key + 100))

    let oldCapacity  = table.capacity
    let oldAllocator = table.allocator
    table.allocator = &reject

    let updateFailed       = Swag.catchPanic(func|&table|() { table.add(7, 700) })
    let preserveFailed     = Swag.catchPanic(func|&table|() { table.add(7, 777, updateValue: false) })
    let findFailed         = Swag.catchPanic(func|&table|() { discard table.findOrAdd(7) })
    let borrowedFindFailed = Swag.catchPanic(func|&table|()
    {
        discard table.findOrAddBorrowed(&table.find(7).key)
    })
    let borrowedUpdateFailed = Swag.catchPanic(func|&table|()
    {
        discard table.addBorrowed(&table.find(7).key, &table.find(8).value)
    })
    table.allocator = oldAllocator

    Swag.require(not updateFailed.raised and
                 not preserveFailed.raised and
                 not findFailed.raised and
                 not borrowedFindFailed.raised and
                 not borrowedUpdateFailed.raised)
    Swag.require(table.capacity == oldCapacity and table.count == 16 and table[7] == 108)
}

// A key or a value read from the table itself can be inserted back: growing rehashes the entries
// they live in, so they are taken out first.
#test
{
    var h: HashTable'(String, String)
    discard h.add("seed", "a value long enough to live outside the inline storage")
    for i in 200
    {
        let key = Format.toString("k%", i)
        discard h.addBorrowed(&key, &h.find("seed").value)
    }

    Swag.require(h.count == 201)
    for _, v in h do
        Swag.require(v[] == "a value long enough to live outside the inline storage")

    var keys: HashTable'(String, s32)
    discard keys.add("first key that is long enough to allocate", 1)
    for i in 100
    {
        discard keys.findOrAdd(Format.toString("%", i))
        discard keys.findOrAddBorrowed(&keys.find("first key that is long enough to allocate").key)
    }

    Swag.require(keys.count == 101 and keys.getOrDefault("first key that is long enough to allocate", 0) == 1)
}

#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertReverseIntTableIteration(table: const &HashTable'(s32, s32))->bool
{
    var forwardKeys: Array's32
    var forwardValues: Array's32
    foreach key, value in table
    {
        forwardKeys.add(key)
        forwardValues.add(value)
    }

    var reverseKeys: Array's32
    var reverseValues: Array's32
    foreach #reverse key, value in table
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
    @assert(table.count == 0)
    @assert(!table.contains(1))
    @assert(table.tryFind(1) == null)

    table.add(1, 10)
    table[1] = 11
    table[3] = 30

    @assert(table.count == 2)
    @assert(table.contains(1))
    @assert(table.contains(3))
    @assert(table.get(9, 99) == 99)
    @assert(table[1] == 11)
    @assert(table[3] == 30)
}

#test
{
    var table: HashTable'(s32, s32)

    var movedValue: s32 = 20
    table.add(2, moveref &movedValue)

    let slot4 = table.findOrAdd(4)
    slot4.value = 40

    let entryTwo = table.find(2)
    entryTwo.value += 2

    @assert(table.count == 2)
    @assert(table[2] == 22)
    @assert(table[4] == 40)
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)
    table.add(4, 40)

    var sumKeys = 0
    var sumValues = 0
    foreach key, value in table
    {
        #assert(#typeof(key) == s32)
        #assert(#typeof(value) == s32)
        sumKeys += key
        sumValues += value
    }

    @assert(sumKeys == 10)
    @assert(sumValues == 103)
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)
    table.add(4, 40)

    @assert(assertReverseIntTableIteration(table))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)

    table.remove(2)
    @assert(!table.contains(2))
    @assert(table.count == 2)

    table.add(2, 200)
    table.add(2, 999, false)
    @assert(table.count == 3)
    @assert(table[2] == 200)

    table.clear()
    @assert(table.count == 0)
    @assert(!table.contains(1))
    @assert(!table.contains(2))
}

func assertTableStringValue(table: const &HashTable'(string, String), key: string, expected: string)->bool
{
    let entry = table.tryFind(key)
    return entry != null and entry.value == expected and @countof(entry.value) == @countof(expected)
}

#test
{
    var original: HashTable'(string, s32)
    original.add("alpha", 1)

    let entry = original.tryFind("alpha")
    @assert(entry != null)
    @assert(entry.value == 1)
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

    @assert(assertTableStringValue(original, "alpha", "one"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    @assert(assertTableStringValue(original, "alpha", "one"))
    @assert(assertTableStringValue(original, "beta", "two"))
    @assert(original.tryFind("gamma") == null)
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    var copy = original
    copy["alpha"] = "uno"
    copy.findOrAdd("gamma").value = "three"

    @assert(assertTableStringValue(original, "alpha", "one"))
    @assert(assertTableStringValue(original, "beta", "two"))
    @assert(original.tryFind("gamma") == null)

    @assert(assertTableStringValue(copy, "alpha", "uno"))
    @assert(assertTableStringValue(copy, "beta", "two"))
    @assert(assertTableStringValue(copy, "gamma", "three"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")
    original.remove("alpha")

    var copy = original
    copy.add("alpha", "uno")

    @assert(original.tryFind("alpha") == null)
    @assert(assertTableStringValue(original, "beta", "two"))

    @assert(assertTableStringValue(copy, "alpha", "uno"))
    @assert(assertTableStringValue(copy, "beta", "two"))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 10)
    table.add(2, 20)

    table.opSet([struct { k: s32, v: s32 }{k: 3, v: 30}])

    @assert(table.count == 1)
    @assert(!table.contains(1))
    @assert(!table.contains(2))
    @assert(table.contains(3))
    @assert(table[3] == 30)
}

#test
{
    var table: HashTable'(s32, s32)
    table.reserve(33)

    table.add(10, 100)
    table.add(42, 420)
    table.add(74, 740)

    @assert(table.capacity >= 33)
    @assert(table.contains(10))
    @assert(table.contains(42))
    @assert(table.contains(74))
    @assert(table[10] == 100)
    @assert(table[42] == 420)
    @assert(table[74] == 740)
}

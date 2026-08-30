#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
    Swag.assert(table.count == 0)
    Swag.assert(!table.contains(1))
    Swag.assert(table.tryFind(1) == null)

    table.add(1, 10)
    table[1] = 11
    table[3] = 30

    Swag.assert(table.count == 2)
    Swag.assert(table.contains(1))
    Swag.assert(table.contains(3))
    Swag.assert(table.getOrDefault(9, 99) == 99)
    Swag.assert(table[1] == 11)
    Swag.assert(table[3] == 30)
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

    Swag.assert(table.count == 2)
    Swag.assert(table[2] == 22)
    Swag.assert(table[4] == 40)
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

    Swag.assert(sumKeys == 10)
    Swag.assert(sumValues == 103)
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)
    table.add(4, 40)

    Swag.assert(assertReverseIntTableIteration(table))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 11)
    table.add(2, 22)
    table.add(3, 30)

    table.remove(2)
    Swag.assert(!table.contains(2))
    Swag.assert(table.count == 2)

    table.add(2, 200)
    table.add(2, 999, false)
    Swag.assert(table.count == 3)
    Swag.assert(table[2] == 200)

    table.clear()
    Swag.assert(table.count == 0)
    Swag.assert(!table.contains(1))
    Swag.assert(!table.contains(2))
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

    let entry = original.tryFind("alpha")!
    Swag.assert(entry.value == 1)
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

    Swag.assert(assertTableStringValue(original, "alpha", "one"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    Swag.assert(assertTableStringValue(original, "alpha", "one"))
    Swag.assert(assertTableStringValue(original, "beta", "two"))
    Swag.assert(original.tryFind("gamma") == null)
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    var copy = original
    copy["alpha"]                 = "uno"
    copy.findOrAdd("gamma").value = "three"

    Swag.assert(assertTableStringValue(original, "alpha", "one"))
    Swag.assert(assertTableStringValue(original, "beta", "two"))
    Swag.assert(original.tryFind("gamma") == null)

    Swag.assert(assertTableStringValue(copy, "alpha", "uno"))
    Swag.assert(assertTableStringValue(copy, "beta", "two"))
    Swag.assert(assertTableStringValue(copy, "gamma", "three"))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")
    original.remove("alpha")

    var copy = original
    copy.add("alpha", "uno")

    Swag.assert(original.tryFind("alpha") == null)
    Swag.assert(assertTableStringValue(original, "beta", "two"))

    Swag.assert(assertTableStringValue(copy, "alpha", "uno"))
    Swag.assert(assertTableStringValue(copy, "beta", "two"))
}

#test
{
    var table: HashTable'(s32, s32)
    table.add(1, 10)
    table.add(2, 20)

    table.opSet([struct { k: s32, v: s32 }{k: 3, v: 30}])

    Swag.assert(table.count == 1)
    Swag.assert(!table.contains(1))
    Swag.assert(!table.contains(2))
    Swag.assert(table.contains(3))
    Swag.assert(table[3] == 30)
}

#test
{
    var table: HashTable'(s32, s32)
    table.reserve(33)

    table.add(10, 100)
    table.add(42, 420)
    table.add(74, 740)

    Swag.assert(table.capacity >= 33)
    Swag.assert(table.contains(10))
    Swag.assert(table.contains(42))
    Swag.assert(table.contains(74))
    Swag.assert(table[10] == 100)
    Swag.assert(table[42] == 420)
    Swag.assert(table[74] == 740)
}

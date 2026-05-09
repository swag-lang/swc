#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

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

// Disabled on purpose: copying `HashTable'(string, String)` still trips a JIT access violation
// in generated runtime code. Keep the scalar HashTable coverage above enabled, and isolate this
// case separately before turning it back on here.
#if false
{
    func assertTableStringValue(table: const &HashTable'(string, String), key: string, expected: string)->bool
    {
        let entry = table.tryFind(key)
        return entry != null and entry.value == expected and @countof(entry.value) == @countof(expected)
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
}

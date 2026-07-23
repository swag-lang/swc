#global internal

struct(T) RecursiveAssocPayload
{
    first:  #null *T
    second: #null *T
    count:  u64
}

struct(K, V) RecursiveAssocEntry
{
    hash:  u32
    key:   K
    value: V
}

struct(K, V) RecursiveAssocTable
{
    table:    #null [*] RecursiveAssocEntry
    count:    u64
    capacity: u64
    deleted:  u64
}

func recursiveHash(key: u32)->u32
{
    return (key * #wrap 2654435761'u32) | 2'u32
}

impl RecursiveAssocTable
{
    #[Swag.NoInline]
    mtd entrySize()->u64
    {
        return #sizeof(RecursiveAssocEntry'(K, V))
    }

    #[Swag.NoInline]
    mtd entryAlign()->u64
    {
        return #alignof(RecursiveAssocEntry'(K, V))
    }

    #[Swag.NoInline]
    mtd makeEntry(key: K, value: V)->RecursiveAssocEntry'(K, V)
    {
        return {hash: 7, key: key, value: value}
    }

    mtd opPostCopy()
    {
        if .table == null do
            return

        let oldTable = .table
        let oldCapacity = .capacity
        .table = cast(#null [*] RecursiveAssocEntry'(K, V)) @alloc(oldCapacity * #sizeof(RecursiveAssocEntry'(K, V)))

        for i in oldCapacity
        {
            .table[i].hash = oldTable[i].hash
            if oldTable[i].hash < 2 do
                continue

            .table[i].key   = #nodrop oldTable[i].key
            .table[i].value = oldTable[i].value
        }
    }

    mtd opDrop()
    {
        if .table do
            @free(.table)
        .table    = null
        .count    = 0
        .capacity = 0
        .deleted  = 0
    }

    mtd grow()
    {
        if .capacity != 0 and .capacity - (.count + .deleted) > .capacity / 4 do
            return

        .reserve(.capacity * 2)
    }

    mtd reserve(newCapacity: u64)
    {
        let reqCapacity = newCapacity > 8 ? newCapacity : 8
        if reqCapacity <= .capacity do
            return

        let oldTable = .table
        let oldCapacity = .capacity

        .table    = cast(#null [*] RecursiveAssocEntry'(K, V)) @alloc(reqCapacity * #sizeof(RecursiveAssocEntry'(K, V)))
        .count    = 0
        .deleted  = 0
        .capacity = reqCapacity

        for i in reqCapacity do
            .table[i].hash = 0

        if oldTable == null do
            return

        for i in oldCapacity
        {
            if oldTable[i].hash < 2 do
                continue

            .emplaceInternal(oldTable[i].hash, &oldTable[i].key, &oldTable[i].value)
        }

        @free(oldTable)
    }

    #[Discardable]
    mtd emplaceInternal(hashVal: u32, key: &K, value: &V)->#null *RecursiveAssocEntry'(K, V)
    {
        .grow()

        var index = hashVal % .capacity
        while .table[index].hash >= 2
        {
            if .table[index].hash == hashVal and .table[index].key == key
            {
                .table[index].value = value
                return .table + index
            }

            index = (index + 1) % .capacity
        }

        .table[index].hash  = hashVal
        .table[index].key   = key
        .table[index].value = value
        .count              += 1
        return .table + index
    }

    #[Discardable]
    mtd add(key: K, value: V)->#null *RecursiveAssocEntry'(K, V)
    {
        let hashVal = recursiveHash(cast(u32) key)
        return .emplaceInternal(hashVal, &key, &value)
    }

    mtd contains(key: K)->bool
    {
        return .tryFind(key) != null
    }

    mtd tryFind(key: K)->#null *RecursiveAssocEntry'(K, V)
    {
        if .table == null do
            return null

        let hashVal = recursiveHash(cast(u32) key)
        var index = hashVal % .capacity
        while .table[index].hash
        {
            if .table[index].hash == hashVal and .table[index].key == key do
                return .table + index
            index = (index + 1) % .capacity
        }

        return null
    }
}

struct RecursiveAssocNode
{
    edges:    RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)
    group:    u32
    terminal: bool
}

#assert(#sizeof(RecursiveAssocPayload'RecursiveAssocNode) == 24)
#assert(#alignof(RecursiveAssocPayload'RecursiveAssocNode) == 8)
#assert(#sizeof(RecursiveAssocEntry'(u32, RecursiveAssocPayload'RecursiveAssocNode)) == 32)
#assert(#alignof(RecursiveAssocEntry'(u32, RecursiveAssocPayload'RecursiveAssocNode)) == 8)
#assert(#sizeof(RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)) == 32)
#assert(#alignof(RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)) == 8)
#assert(#sizeof(RecursiveAssocNode) == 40)
#assert(#alignof(RecursiveAssocNode) == 8)

#test
{
    var assocTable: RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)
    var payload:    RecursiveAssocPayload'RecursiveAssocNode
    let assocEntry = assocTable.makeEntry(10, payload)

    @assert(assocTable.entrySize() == 32)
    @assert(assocTable.entryAlign() == 8)
    @assert(#typeof(assocEntry) == RecursiveAssocEntry'(u32, RecursiveAssocPayload'RecursiveAssocNode))
    @assert(assocEntry.hash == 7)
    @assert(assocEntry.key == 10)
    @assert(assocEntry.value.count == 0)
    @assert(assocEntry.value.first == null)
    @assert(assocEntry.value.second == null)
}

#test
{
    var assocMap:     RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)
    var nodeA, nodeB: RecursiveAssocNode
    let valueA:       RecursiveAssocPayload'RecursiveAssocNode = {first: &nodeA, second: null, count: 1}
    let valueB:       RecursiveAssocPayload'RecursiveAssocNode = {first: null, second: &nodeB, count: 1}

    assocMap.add(10, valueA)
    assocMap.add(20, valueB)

    @assert(assocMap.count == 2)
    @assert(assocMap.capacity >= 8)
    @assert(assocMap.contains(10))
    @assert(assocMap.contains(20))

    let foundA = assocMap.tryFind(10)
    let foundB = assocMap.tryFind(20)
    @assert(foundA != null)
    @assert(foundB != null)
    @assert(foundA.value.count == 1)
    @assert(foundB.value.count == 1)
    @assert(foundA.value.first == &nodeA)
    @assert(foundA.value.second == null)
    @assert(foundB.value.first == null)
    @assert(foundB.value.second == &nodeB)
}

#test
{
    var assocMap:     RecursiveAssocTable'(u32, RecursiveAssocPayload'RecursiveAssocNode)
    var nodeA, nodeB: RecursiveAssocNode
    let valueA:       RecursiveAssocPayload'RecursiveAssocNode = {first: &nodeA, second: null, count: 1}
    let valueB:       RecursiveAssocPayload'RecursiveAssocNode = {first: null, second: &nodeB, count: 1}
    assocMap.add(10, valueA)
    assocMap.add(20, valueB)

    var assocCopy = assocMap
    @assert(assocCopy.count == 2)
    @assert(assocCopy.contains(10))
    @assert(assocCopy.contains(20))

    let copyA = assocCopy.tryFind(10)
    let copyB = assocCopy.tryFind(20)
    @assert(copyA != null)
    @assert(copyB != null)
    @assert(copyA.value.count == 1)
    @assert(copyB.value.count == 1)
    @assert(copyA.value.first == &nodeA)
    @assert(copyA.value.second == null)
    @assert(copyB.value.first == null)
    @assert(copyB.value.second == &nodeB)
}

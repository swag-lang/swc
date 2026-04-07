#global fileprivate

// Real-life example: a generic hash table with open addressing and injected
// hash/equality callbacks so the storage stays reusable across key types.

const DefaultCapacity = 8'u64
const SlotEmpty       = 0'u8
const SlotUsed        = 1'u8

struct(K, V) HashEntry
{
    key:   K
    value: V
}

struct(K, V) HashTable
{
    entries:  [*] HashEntry'(K, V)
    states:   [*] u8
    count:    u64
    capacity: u64
    hashFn:   func(K)->u64
    eqFn:     func(K, K)->bool
}

func(K, V) allocateStorage(table: *HashTable'(K, V), capacity: u64)
{
    table.entries  = cast([*] HashEntry'(K, V)) @alloc(capacity * #sizeof(HashEntry'(K, V)))
    table.states   = cast([*] u8) @alloc(capacity * #sizeof(u8))
    table.capacity = capacity
    table.count    = 0

    for i in capacity do
        table.states[i] = SlotEmpty
}

func(K, V) create(hashFn: func(K)->u64, eqFn: func(K, K)->bool)->HashTable'(K, V)
{
    var result: HashTable'(K, V)
    result.hashFn = hashFn
    result.eqFn   = eqFn
    allocateStorage'(K, V)(&result, DefaultCapacity)
    return result
}

func(K, V) destroy(table: *HashTable'(K, V))
{
    if table.entries do
        @free(table.entries)
    if table.states do
        @free(table.states)

    table.entries  = null
    table.states   = null
    table.count    = 0
    table.capacity = 0
}

func(K, V) insertAssumeSpace(table: *HashTable'(K, V), key: K, value: V)
{
    let start = table.hashFn(key) % table.capacity
    var idx   = start

    while true
    {
        if table.states[idx] == SlotEmpty
        {
            table.states[idx]      = SlotUsed
            table.entries[idx].key = key
            table.entries[idx].value = value
            table.count += 1
            return
        }

        if table.eqFn(table.entries[idx].key, key)
        {
            table.entries[idx].value = value
            return
        }

        idx = (idx + 1) % table.capacity
        @assert(idx != start)
    }
}

func(K, V) rehash(table: *HashTable'(K, V), newCapacity: u64)
{
    let oldEntries  = table.entries
    let oldStates   = table.states
    let oldCapacity = table.capacity

    allocateStorage'(K, V)(table, newCapacity)

    for i in oldCapacity
    {
        if oldStates[i] == SlotUsed do
            insertAssumeSpace'(K, V)(table, oldEntries[i].key, oldEntries[i].value)
    }

    if oldEntries do
        @free(oldEntries)
    if oldStates do
        @free(oldStates)
}

func(K, V) ensureOneMoreSlot(table: *HashTable'(K, V))
{
    if (table.count + 1) * 10 >= table.capacity * 7 do
        rehash'(K, V)(table, table.capacity * 2)
}

func(K, V) put(table: *HashTable'(K, V), key: K, value: V)
{
    ensureOneMoreSlot'(K, V)(table)
    insertAssumeSpace'(K, V)(table, key, value)
}

func(K, V) tryGet(table: *HashTable'(K, V), key: K)->*V
{
    if table.count == 0 do
        return null

    let start = table.hashFn(key) % table.capacity
    var idx   = start

    while true
    {
        if table.states[idx] == SlotEmpty do
            return null

        if table.eqFn(table.entries[idx].key, key) do
            return &table.entries[idx].value

        idx = (idx + 1) % table.capacity
        if idx == start do
            return null
    }
}

func(K, V) contains(table: *HashTable'(K, V), key: K)->bool
{
    return tryGet'(K, V)(table, key) != null
}

func(K, V) getOr(table: *HashTable'(K, V), key: K, fallback: V)->V
{
    let ptr = tryGet'(K, V)(table, key)
    if ptr == null do
        return fallback
    return dref ptr
}

func hashU64(value: u64)->u64
{
    return value * #wrap 11400714819323198485'u64
}

func eqU64(a: u64, b: u64)->bool => a == b
func eqS32(a: s32, b: s32)->bool => a == b
func eqString(a: string, b: string)->bool => a == b

func hashS32(value: s32)->u64
{
    return hashU64(cast(u64) cast(u32) value)
}

func hashString(text: string)->u64
{
    let bytes = cast(const [..] u8) text
    var hash  = 1469598103934665603'u64

    foreach byte in bytes
    {
        hash ^= cast(u64) byte
        hash = hash * #wrap 1099511628211'u64
    }

    return hash
}

func hashAlwaysCollide(value: s32)->u64
{
    return 1'u64
}

struct InventoryRow
{
    sku:      string
    quantity: s32
}

// ---------------------------------------------------------------------------
// Test: string -> s32, update existing key, pointer-based read/write
// ---------------------------------------------------------------------------

#test
{
    var table = create'(string, s32)(&hashString, &eqString)
    defer destroy'(string, s32)(&table)

    put'(string, s32)(&table, "apples", 12)
    put'(string, s32)(&table, "bananas", 7)
    put'(string, s32)(&table, "apples", 20)

    @assert(table.count == 2)
    @assert(contains'(string, s32)(&table, "apples"))
    @assert(contains'(string, s32)(&table, "bananas"))
    @assert(!contains'(string, s32)(&table, "pears"))
    @assert(getOr'(string, s32)(&table, "apples", -1) == 20)
    @assert(getOr'(string, s32)(&table, "pears", -1) == -1)

    let ptr = tryGet'(string, s32)(&table, "bananas")
    @assert(ptr != null)
    dref ptr += 5
    @assert(getOr'(string, s32)(&table, "bananas", -1) == 12)
}

// ---------------------------------------------------------------------------
// Test: s32 -> string with deliberate collisions
// ---------------------------------------------------------------------------

#test
{
    var table = create'(s32, string)(&hashAlwaysCollide, &eqS32)
    defer destroy'(s32, string)(&table)

    put'(s32, string)(&table, 10, "ten")
    put'(s32, string)(&table, 20, "twenty")
    put'(s32, string)(&table, 30, "thirty")
    put'(s32, string)(&table, 40, "forty")

    @assert(table.count == 4)
    @assert(getOr'(s32, string)(&table, 10, "missing") == "ten")
    @assert(getOr'(s32, string)(&table, 20, "missing") == "twenty")
    @assert(getOr'(s32, string)(&table, 30, "missing") == "thirty")
    @assert(getOr'(s32, string)(&table, 40, "missing") == "forty")
    @assert(getOr'(s32, string)(&table, 99, "missing") == "missing")
}

// ---------------------------------------------------------------------------
// Test: u64 -> u64, grow and rehash many values
// ---------------------------------------------------------------------------

#test
{
    var table = create'(u64, u64)(&hashU64, &eqU64)
    defer destroy'(u64, u64)(&table)

    for i in 100'u64 do
        put'(u64, u64)(&table, i, i * i + 3)

    @assert(table.count == 100)
    @assert(table.capacity >= 128)
    @assert(getOr'(u64, u64)(&table, 0, 0) == 3)
    @assert(getOr'(u64, u64)(&table, 10, 0) == 103)
    @assert(getOr'(u64, u64)(&table, 99, 0) == 9804)
    @assert(getOr'(u64, u64)(&table, 1_000, 55) == 55)
}

// ---------------------------------------------------------------------------
// Test: string -> struct, generic value payload
// ---------------------------------------------------------------------------

#test
{
    var table = create'(string, InventoryRow)(&hashString, &eqString)
    defer destroy'(string, InventoryRow)(&table)

    put'(string, InventoryRow)(&table, "hammer", {sku: "HM-01", quantity: 8})
    put'(string, InventoryRow)(&table, "screwdriver", {sku: "SD-02", quantity: 14})

    let hammer = getOr'(string, InventoryRow)(&table, "hammer", {sku: "missing", quantity: -1})
    let drill  = getOr'(string, InventoryRow)(&table, "drill", {sku: "missing", quantity: -1})

    @assert(hammer.sku == "HM-01")
    @assert(hammer.quantity == 8)
    @assert(drill.sku == "missing")
    @assert(drill.quantity == -1)
}

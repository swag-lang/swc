#global export

using Swag

// Represents a single key-value pair entry within a HashTable.
struct(K, V) HashTableEntry
{
    internal
    hash: u32
    readonly
    key:   K     // The key.
    value: V     // The value associated with the key.
}

// A hash table implemented with open-addressing that maps keys to values.
// It provides fast lookups, additions, and removals of key-value pairs.
struct(K, V) HashTable
{
    // Special hash values to indicate the state of a slot in the table.
    #[Swag.NoDoc]
    const HASH_FREE = 0'u32
    #[Swag.NoDoc]
    const HASH_DELETED = 1'u32
    #[Swag.NoDoc]
    const HASH_FIRST = 2'u32

    internal
    allocator: #null IAllocator

    // Sizes are reported, never set: the table grows itself when it needs to.
    readonly
    {
        count:    u64     // The number of valid key-value pairs currently in the table.
        capacity: u64     // The total number of slots, always a power of two.
    }

    // Open-addressing state. The layout is an implementation choice: reaching into it from
    // outside would tie callers to the probing scheme and the load factor.
    private
    {
        table:         #null [*] HashTableEntry     // Contiguous memory block for the slots.
        deleted:       u64                          // The number of slots marked as deleted.
        growThreshold: u64                          // Used slot count that triggers a resize, derived from 'capacity'.
    }
}

impl HashTable
{
    #[Swag.NoDoc]
    func normalizeCapacity(newCapacity: u64)->u64
    {
        var result = 32'u64
        let target = Math.max(newCapacity, result)
        while result < target do
            result <<= 1
        return result
    }

    #[Swag.NoDoc]
    mtd tablePtr()->[*] HashTableEntry
    {
        return .table orelse cast([*] HashTableEntry'(K, V)) 1'u64
    }

    #[Swag.NoDoc]
    mtd const constTablePtr()->const [*] HashTableEntry
    {
        return cast(const [*] HashTableEntry'(K, V)) (.table orelse cast([*] HashTableEntry'(K, V)) 1'u64)
    }

    // Returns the number of key-value pairs in the me.table.
    #[Inline]
    mtd opCount()->u64
    {
        return .count
    }

    // Ensures the allocated memory is freed when the me.table goes out of scope.
    mtd opDrop()
    {
        .free()
    }

    // Replaces the content of the me.table with key-value pairs from a slice.
    mtd opSet(slice: const [..] { k: K, v: V })
    {
        .clear()
        for v in slice do
            .add(v.k, v.v)
    }

    // Handles the deep copy of the me.table when it is copied.
    // A new me.table is allocated and all entries are copied over.
    mtd opPostCopy()
    {
        if !.table do
            return

        if !.allocator do
            .allocator = @getcontext().allocator

        let oldTable = .tablePtr()
        let newTable = cast([*] HashTableEntry'(K, V)) Memory.alloc(.capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
        Memory.clear(newTable, .capacity * #sizeof(HashTableEntry'(K, V)))
        #static if Reflection.hasPostCopy(K) or Reflection.hasPostCopy(V)
        {
            for [i] in .capacity
            {
                let hashVal = oldTable[i].hash
                if hashVal < HashTable.HASH_DELETED do
                    continue

                newTable[i].hash  = hashVal
                newTable[i].key   = #nodrop oldTable[i].key
                newTable[i].value = #nodrop oldTable[i].value
            }
        }
        else
        {
            Memory.copy(newTable, oldTable, .capacity * #sizeof(HashTableEntry'(K, V)))
        }

        .table = newTable
    }

    // Provides read-only access to the value associated with a key.
    // Asserts if the key is not found.
    mtd const opIndex(key: K)->const &V
    {
        let it = .find(key)
        return &it.value
    }

    // Provides mutable access to the value associated with a key.
    // Asserts if the key is not found. See [[opIndexSet]] for insertion or update.
    mtd opIndex(key: K)->&V
    {
        let it = .find(key)
        return &it.value
    }

    // Assigns a value to a key, updating it if it exists or adding it if it doesn't.
    mtd opIndexSet(key: K, val: V)
    {
        .add(key, val)
    }

    // Provides a way to iterate over each key-value pair in the me.table.
    // This is a macro that accepts a code block to execute for each pair.
    // Block parameters: 'key' and 'value' (values, or pointers when visiting by pointer).
    #[Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(key, value))
    {
        if !.count do
            return

        let table  = .constTablePtr()
        var remain = .count
        #scope(Up)
            for .capacity
        {
            #static if back do
                let tableIndex = .capacity - @index - 1
            else do
                let tableIndex = @index

            if table[tableIndex].hash < HashTable.HASH_FIRST do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &table[tableIndex].key, value = cast(&V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const &K) &table[tableIndex].key, value = cast(const &V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(V) do
                    #inject(stmt, key = table[tableIndex].key, value = cast(const &V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if !remain do
                break
        }
    }

    // Computes the hash for a given key.
    // Ensures the resulting hash is not one of the reserved values (FREE, me.deleted).
    //
    // Only the two reserved values are lifted, never a whole bit: forcing a bit on
    // would make every starting probe index share it, so half of the slots could
    // only ever be reached by probing.
    #[Inline, Swag.NoDoc]
    func hashKey(key: K)->u32
    {
        let hashVal = Hash.hash32(key)
        return hashVal < HashTable.HASH_FIRST ? HashTable.HASH_FIRST : hashVal
    }

    // Frees the hash me.table's memory and resets its state.
    // If keys or values have destructors, they are called.
    mtd free()
    {
        if !.table do
            return
        let table = .tablePtr()

        // Need to drop every structs
        #static if Reflection.hasDrop(#typeof(K)) or Reflection.hasDrop(#typeof(V))
        {
            for [i] in .capacity where table[i].hash >= HashTable.HASH_DELETED
            {
                @drop(&table[i].key)
                @drop(&table[i].value)
            }
        }

        Memory.free(table, .capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
        .table = null
        .count, .capacity, .deleted, .growThreshold = 0
    }

    // Checks if the me.table needs to be resized and triggers it if necessary.
    // Growth happens when the load factor (including me.deleted slots) exceeds 50%.
    #[Inline, Swag.NoDoc]
    mtd grow()
    {
        // Every insertion path runs this, so it is a single compare against a threshold
        // computed once per resize. An empty me.table has a zero threshold and falls through.
        if .count + .deleted < .growThreshold do
            return

        .reserve(.capacity * 2)
    }

    // Resizes the hash me.table to a new me.capacity, rehashing all existing elements.
    mtd reserve(newCapacity: u64)
    {
        let reqCapacity = normalizeCapacity(newCapacity)
        if reqCapacity <= .capacity do
            return

        let oldTable = .table
        .count, .deleted = 0
        let newCapacityBytes = reqCapacity * #sizeof(HashTableEntry'(K, V))

        if !.allocator do
            .allocator = @getcontext().allocator
        .table = cast([*] HashTableEntry'(K, V)) Memory.alloc(newCapacityBytes, .allocator)
        let table = .tablePtr()

        // Be sure hash entry is 0
        Memory.clear(table, newCapacityBytes)

        // Copy the last me.table to the new me.table, removing me.deleted entries
        let oldCapacity = .capacity
        .capacity      = reqCapacity
        .growThreshold = reqCapacity / 2
        let oldTablePtr = oldTable orelse cast([*] HashTableEntry'(K, V)) 1'u64
        for [i] in oldCapacity
        {
            let h = oldTablePtr[i].hash
            if h >= HashTable.HASH_FIRST
            {
                .emplaceInternal(h, &oldTablePtr[i].key, &oldTablePtr[i].value)
            }
            elif h == HashTable.HASH_DELETED
            {
                @drop(&oldTablePtr[i].key)
                @drop(&oldTablePtr[i].value)
            }
        }

        Memory.free(oldTable, oldCapacity * #sizeof(HashTableEntry'(K, V)), .allocator)
    }

    // Finds the correct index for a new key, handling collisions and me.deleted slots.
    // Uses linear probing to find the next available slot.
    //
    // Both loops test the cached hash first: an occupied slot that does not match is by far
    // the most frequent outcome, and it must cost a single compare. A table that has never
    // seen a removal takes the shorter loop, which has no deleted slot to remember.
    #[Swag.NoDoc]
    mtd getNewIndex(key: K, idx: u64, hashVal: u64)->u64
    {
        let mask  = .capacity - 1
        var index = idx
        let table = .tablePtr()

        if !.deleted
        {
            for
            {
                let entryHash = table[index].hash
                if entryHash == hashVal
                {
                    if table[index].key == key do
                        return index
                }
                elif entryHash == HashTable.HASH_FREE do
                    return index

                index = (index + 1) & mask
            }
        }

        var firstDeleted = Swag.U64.Max
        for
        {
            let entryHash = table[index].hash
            if entryHash == hashVal
            {
                if table[index].key == key do
                    return index
            }
            elif entryHash < HashTable.HASH_FIRST
            {
                if entryHash == HashTable.HASH_FREE do
                    return firstDeleted != Swag.U64.Max ? firstDeleted : index
                if firstDeleted == Swag.U64.Max do
                    firstDeleted = index
            }

            index = (index + 1) & mask
        }
    }

    // Adds a new key-value pair to the me.table. The key is always copied.
    // The value is copied; pass it with '#move' to move it instead.
    // If the key already exists, the value is updated if 'updateValue' is true.
    #[Discardable]
    mtd add(key: K, value: #fwd V, updateValue = true)->*HashTableEntry
        where Reflection.canCopy(#typeof(K))
    {
        .grow()

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST
        {
            if updateValue do
                table[index].value = #fwd value
            return table + index
        }

        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #nodrop key
            table[index].value = #nodrop #fwd value
        }
        else
        {
            if table[index].hash == HashTable.HASH_DELETED do
                .deleted -= 1
            table[index].key   = key
            table[index].value = #fwd value
        }

        table[index].hash = hashVal
        .count            += 1
        return table + index
    }

    // Internal helper to add a new element with a pre-computed hash. Use with care.
    #[Discardable, Swag.NoDoc]
    mtd emplaceInternal(hashVal: u32, key: &K, value: &V)->*HashTableEntry
        where Reflection.canCopy(#typeof(K)) and Reflection.canCopy(#typeof(V))
    {
        .grow()

        var index = cast(u64) hashVal & (.capacity - 1)
        let table = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST
        {
            @drop(&table[index].value)
            table[index].value = #relocate value
            return table + index
        }

        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #relocate key
            table[index].value = #relocate value
        }
        else
        {
            if table[index].hash == HashTable.HASH_DELETED do
                .deleted -= 1
            @drop(&table[index].key)
            @drop(&table[index].value)
            table[index].key   = #relocate key
            table[index].value = #relocate value
        }

        table[index].hash = hashVal
        .count            += 1
        return table + index
    }

    // Removes a key-value pair from the me.table by key.
    // If the key exists, its slot is marked as 'DELETED'. Does nothing if the key is not found.
    mtd remove(key: K)
    {
        if !.table do
            return

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key
            {
                table[index].hash = HashTable.HASH_DELETED
                .count            -= 1
                .deleted          += 1
                return
            }

            index = (index + 1) & mask
        }
    }

    // Returns 'true' if the me.table contains the given key.
    mtd const contains(key: K)->bool
    {
        if !.table do
            return false

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .constTablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return true
            index = (index + 1) & mask
        }

        return false
    }

    // Tries to find the entry for a given key.
    // Returns a pointer to the 'HashTableEntry' if found, otherwise returns 'null'.
    mtd tryFind(key: K)->#null *HashTableEntry
    {
        if !.table do
            return null

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        // Read each slot hash once, and test the match before the end of chain: a lookup walks
        // occupied slots, so that is the compare worth putting first
        for
        {
            let entryHash = table[index].hash
            if entryHash == hashVal
            {
                if table[index].key == key do
                    return table + index
            }
            elif entryHash == HashTable.HASH_FREE do
                return null

            index = (index + 1) & mask
        }
    }

    // Tries to find the entry for a given key.
    // Returns a pointer to the 'HashTableEntry' if found, otherwise returns 'null'.
    mtd const tryFind(key: K)->#null const *HashTableEntry
    {
        if !.table do
            return null

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .constTablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return table + index
            index = (index + 1) & mask
        }

        return null
    }

    // Finds the entry for a given key.
    // Asserts and will likely crash if the key is not found. Use [[tryFind]] for safe searching.
    mtd find(key: K)->*HashTableEntry
    {
        let result = .tryFind(key)
        Debug.assert(result != null, "key not found")
        return result!
    }

    // Finds the entry for a given key.
    // Asserts and will likely crash if the key is not found. Use [[tryFind]] for safe searching.
    mtd const find(key: K)->const *HashTableEntry
    {
        let result = .tryFind(key)
        Debug.assert(result != null, "key not found")
        return result!
    }

    // Gets the value associated with a key.
    // If the key does not exist, returns the provided default value 'val' instead.
    mtd const getOrDefault(key: K, defaultValue: V)->V
    {
        let it = .tryFind(key)
        if !it do
            return defaultValue
        return it.value
    }

    // Finds the entry for a key, or adds a new entry with a default-initialized value if not found.
    // Returns a pointer to the existing or new entry.
    // The key is hashed and probed once, whether it is found or inserted, instead of
    // paying a full lookup and then a full insert on every miss.
    mtd findOrAdd(key: K)->*HashTableEntry
        where Reflection.canCopy(#typeof(K))
    {
        .grow()

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST do
            return table + index

        var val: V
        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #nodrop key
            table[index].value = #nodrop val
        }
        else
        {
            .deleted           -= 1
            table[index].key   = key
            table[index].value = val
        }

        table[index].hash = hashVal
        .count            += 1
        return table + index
    }

    // Removes all elements from the me.table without deallocating the me.table memory.
    // All slots are marked as 'FREE'.
    mtd clear()
    {
        // Need to put the 'hash' value of each entry to HASH_FREE
        // Drop the key and the value if necessary
        if .count or .deleted
        {
            let table = .tablePtr()
            for [i] in .capacity
            {
                let hashval = table[i].hash

                if hashval >= HashTable.HASH_DELETED
                {
                    @drop(&table[i].key)
                    @drop(&table[i].value)
                }

                if hashval == HashTable.HASH_DELETED do
                    .deleted -= 1
                elif hashval >= HashTable.HASH_FIRST do
                    .count -= 1
                table[i].hash = HashTable.HASH_FREE

                // We are done if there's no more valid value, and no more me.deleted value
                if !.count and !.deleted do
                    break
            }
        }
    }
}

impl StrConv.IConvert for HashTable
{
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: #null string)
    {
        buf.addBytes("[")
        for k, [v] in me
        {
            if @index do
                buf.addBytes(", ")

            buf.addBytes("key = ")
            StrConv.convert'K(buf, k, convFmt, strFormat)
            buf.addBytes(" value = ")
            StrConv.convert'V(buf, v, convFmt, strFormat)
        }

        buf.addBytes("]")
    }
}

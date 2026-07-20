#global export
using Swag

// Represents a single key-value pair entry within a HashTable.
struct(K, V) HashTableEntry
{
    hash:      u32     // The cached hash of the key.
    key:       K       // The key.
    value:     V       // The value associated with the key.
}

// A hash me.table implemented with open-addressing that maps keys to values.
// It provides fast lookups, additions, and removals of key-value pairs.
struct(K, V) HashTable
{
    // Special hash values to indicate the state of a slot in the me.table.
    const HASH_FREE        = 0'u32                // The slot is empty and has never been used.
    const HASH_DELETED     = 1'u32                // The slot was previously occupied but has been me.deleted.
    const HASH_FIRST       = 2'u32                // The first possible valid hash value.
    const HASH_MASK        = 2'u32                // A mask to ensure that valid hashes are >= HASH_FIRST.

    allocator:             #null IAllocator             // The me.allocator used for memory operations.
    table:                 #null [*] HashTableEntry     // Pointer to the contiguous memory block for the hash me.table.
    count:                 u64                    // The number of valid key-value pairs currently in the me.table.
    capacity:              u64                    // The total number of slots in the hash me.table.
    deleted:               u64                    // The number of slots marked as me.deleted.
}

impl HashTable
{
    func normalizeCapacity(newCapacity: u64)->u64
    {
        var result = 32'u64
        let target = Math.max(newCapacity, result)
        while result < target do
            result <<= 1
        return result
    }

    mtd tablePtr()->[*] HashTableEntry
    {
        return .table orelse cast([*] HashTableEntry'(K, V)) 1'u64
    }

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
    mtd opSet(slice: #null const [..] { k: K, v: V })
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

        if .allocator == null do
            .allocator = @getcontext().allocator

        let oldTable = .tablePtr()
        let newTable = cast([*] HashTableEntry'(K, V)) Memory.alloc(.capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
        Memory.clear(newTable, .capacity * #sizeof(HashTableEntry'(K, V)))
        #if Reflection.hasPostCopy(K) or Reflection.hasPostCopy(V)
        {
            for i in .capacity
            {
                let hashVal = oldTable[i].hash
                if hashVal < HashTable.HASH_DELETED do
                    continue

                newTable[i].hash  = hashVal
                newTable[i].key   = #nodrop oldTable[i].key
                newTable[i].value = #nodrop oldTable[i].value
            }
        }
        #else
        {
            Memory.copy(newTable, oldTable, .capacity * #sizeof(HashTableEntry'(K, V)))
        }

        .table = newTable
    }

    // Provides read-only access to the value associated with a key.
    // Asserts if the key is not found.
    mtd const opIndex(key: K)->const &V
    {
        #[Global]
        var d: V = undefined

        let it = .find(key)
        if it do
            return &it.value
        return &d
    }

    // Provides mutable access to the value associated with a key.
    // If the key does not exist, this will exhibit undefined behavior. Use with caution.
    // See [[opIndexSet]] for safe insertion/update.
    mtd opIndex(key: K)->&V
    {
        #[Global]
        var d: V = undefined

        let it = .tryFind(key)
        if it do
            return &it.value
        return &d
    }

    // Assigns a value to a key, updating it if it exists or adding it if it doesn't.
    mtd opIndexSet(key: K, val: V)
    {
        let it = .tryFind(key)
        if it do
            it.value = val
        else do
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

        let table = .constTablePtr()
        var remain = .count
        #scope(Up)
        for .capacity
        {
            #if back do
                let tableIndex = .capacity - @index - 1
            #else do
                let tableIndex = @index

            if table[tableIndex].hash < HashTable.HASH_FIRST do
                continue

            #scope(Down)
            {
                #if ptr do
                    #inject(stmt, key = cast(&K) &table[tableIndex].key, value = cast(&V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                #elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const &K) &table[tableIndex].key, value = cast(const &V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                #elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
                #elif Reflection.isStruct(V) do
                    #inject(stmt, key = table[tableIndex].key, value = cast(const &V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                #else do
                    #inject(stmt, key = table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if !remain do
                break
        }
    }

    // Computes the hash for a given key.
    // Ensures the resulting hash is not one of the reserved values (FREE, me.deleted).
    #[Inline]
    func hashKey(key: K)->u32
    {
        return Hash.hash32(key) | HashTable.HASH_MASK
    }

    // Frees the hash me.table's memory and resets its state.
    // If keys or values have destructors, they are called.
    mtd free()
    {
        if !.table do
            return
        let table = .tablePtr()

        // Need to drop every structs
        #if Reflection.hasDrop(#typeof(K)) or Reflection.hasDrop(#typeof(V))
        {
            for i in .capacity where table[i].hash >= HashTable.HASH_DELETED
            {
                @drop(&table[i].key)
                @drop(&table[i].value)
            }
        }

        Memory.free(table, .capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
        .table = null
        .count, .capacity, .deleted = 0
    }

    // Checks if the me.table needs to be resized and triggers it if necessary.
    // Growth happens when the load factor (including me.deleted slots) exceeds 75%.
    mtd grow()
    {
        // We need to trigger the growing of the me.table is there's not enough room
        if .capacity != 0 and .capacity - (.count + .deleted) > .capacity / 4 do
            return

        let newCapacity = .capacity * 2
        .reserve(newCapacity)
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

        if .allocator == null do
            .allocator = @getcontext().allocator
        .table = cast([*] HashTableEntry'(K, V)) Memory.alloc(newCapacityBytes, .allocator)
        let table = .tablePtr()

        // Be sure hash entry is 0
        Memory.clear(table, newCapacityBytes)

        // Copy the last me.table to the new me.table, removing me.deleted entries
        let oldCapacity = .capacity
        .capacity = reqCapacity
        let oldTablePtr = oldTable orelse cast([*] HashTableEntry'(K, V)) 1'u64
        for i in oldCapacity
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
    mtd getNewIndex(key: K, idx: u64, hashVal: u64)->u64
    {
        var firstDeleted = Swag.U64.Max
        let mask         = .capacity - 1
        var index        = idx
        let table        = .tablePtr()

        for
        {
            let entryHash = table[index].hash
            if entryHash == HashTable.HASH_FREE do
                return firstDeleted != Swag.U64.Max ? firstDeleted : index

            if entryHash == HashTable.HASH_DELETED and firstDeleted == Swag.U64.Max do
                firstDeleted = index

            if entryHash == hashVal and table[index].key == key do
                return index

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
        .count += 1
        return table + index
    }

    // Internal helper to add a new element with a pre-computed hash. Use with care.
    #[Discardable]
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
        .count += 1
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
                .count -= 1
                .deleted += 1
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

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return table + index
            index = (index + 1) & mask
        }

        return null
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
        Debug.assert(.table != null)

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return table + index
            index = (index + 1) & mask
        }

        unreachable
    }

    // Finds the entry for a given key.
    // Asserts and will likely crash if the key is not found. Use [[tryFind]] for safe searching.
    mtd const find(key: K)->const *HashTableEntry
    {
        Debug.assert(.table != null)

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

        unreachable
    }

    // Gets the value associated with a key.
    // If the key does not exist, returns the provided default value 'val' instead.
    mtd const get(key: K, val: V)->V
    {
        let it = .tryFind(key)
        if !it do
            return val
        return it.value
    }

    // Finds the entry for a key, or adds a new entry with a default-initialized value if not found.
    // Returns a pointer to the existing or new entry.
    mtd findOrAdd(key: K)->*HashTableEntry
    {
        let it = .tryFind(key)
        if it do
            return it orelse cast(*HashTableEntry) 1'u64
        var val: V
        return .add(key, val)
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
            for i in .capacity
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
        for k, v in me
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

#global export

using Swag

// Represents a single entry within a HashSet.
struct(K) HashSetEntry
{
    hash: u32     // The cached hash of the key.
    key:  K       // The key itself.
}

// A hash set implemented with an open-addressing hash table.
// It stores a collection of unique keys, providing fast lookups, additions, and removals.
struct(K) HashSet
{
    // Special hash values to indicate the state of a slot in the table.
    const HASH_FREE    = 0'u32     // The slot is empty and has never been used.
    const HASH_DELETED = 1'u32     // The slot was previously occupied but has been deleted.
    const HASH_FIRST   = 2'u32     // The first possible valid hash value.

    allocator: #null IAllocator     // The allocator used for memory operations.

    // Sizes are reported, never set: the set grows itself when it needs to.
    readonly
    {
        count:    u64 // The number of valid elements currently in the set.
        capacity: u64 // The total number of slots in the hash table.
    }

    // Open-addressing state. The layout is an implementation choice: reaching into it from
    // outside would tie callers to the probing scheme and the load factor.
    private
    {
        table:   #null [*] HashSetEntry // Contiguous memory block for the slots.
        deleted: u64 // The number of slots marked as deleted.
    }
}

impl HashSet
{
    func normalizeCapacity(newCapacity: u64)->u64
    {
        var result = 32'u64
        let target = Math.max(newCapacity, result)
        while result < target do
            result <<= 1
        return result
    }

    mtd tablePtr()->[*] HashSetEntry
    {
        return .table orelse cast([*] HashSetEntry'(K)) 1'u64
    }

    mtd const constTablePtr()->const [*] HashSetEntry
    {
        return cast(const [*] HashSetEntry'(K)) (.table orelse cast([*] HashSetEntry'(K)) 1'u64)
    }

    // Returns the number of elements in the set.
    #[Inline]
    mtd opCount()->u64
    {
        return .count
    }

    // Ensures the allocated memory is freed when the set goes out of scope.
    mtd opDrop()
    {
        .free()
    }

    // Replaces the content of the set with elements from a slice.
    mtd opSet(slice: const [..] K)
    {
        .clear()
        for v in slice do
            .add(v)
    }

    // Handles the deep copy of the set when it is copied.
    // A new me.table is allocated and all entries are copied over.
    mtd opPostCopy()
    {
        if !.table do
            return

        if !.allocator do
            .allocator = @getcontext().allocator

        let oldTable = .tablePtr()
        let newTable = cast([*] HashSetEntry'(K)) Memory.alloc(.capacity * #sizeof(HashSetEntry'(K)), .allocator)
        Memory.clear(newTable, .capacity * #sizeof(HashSetEntry'(K)))
        #static if Reflection.hasPostCopy(K)
        {
            for [i] in .capacity
            {
                let hashVal = oldTable[i].hash
                if hashVal < HashSet.HASH_DELETED do
                    continue

                newTable[i].hash = hashVal
                newTable[i].key  = #nodrop oldTable[i].key
            }
        }
        else
        {
            Memory.copy(newTable, oldTable, .capacity * #sizeof(HashSetEntry'(K)))
        }

        .table = newTable
    }

    // Provides a way to iterate over each key in the set.
    // This is a macro that accepts a code block to execute for each key.
    // Block parameter: 'key' is the key (or a pointer to it).
    #[Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(key))
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

            if table[tableIndex].hash < HashSet.HASH_FIRST do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, break = break to Up, continue = break to Down)
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
    #[Inline]
    func hashKey(key: K)->u32
    {
        let hashVal = Hash.hash32(key)
        return hashVal < HashSet.HASH_FIRST ? HashSet.HASH_FIRST : hashVal
    }

    // Frees the hash set's memory and resets its state.
    // If keys have destructors, they are called.
    mtd free()
    {
        if !.table do
            return
        let table = .tablePtr()

        // Need to drop every structs
        #static if Reflection.hasDrop(#typeof(K))
        {
            for [i] in .capacity
            {
                if table[i].hash >= HashSet.HASH_DELETED do
                    @drop(&table[i].key)
            }
        }

        Memory.free(table, .capacity * #sizeof(HashSetEntry'(K)), .allocator)
        .table                      = null
        .count, .capacity, .deleted = 0
    }

    // Checks if the me.table needs to be resized and triggers it if necessary.
    // Growth happens when the load factor (including me.deleted slots) exceeds 50%.
    mtd grow()
    {
        // Linear probing degrades sharply past half full: a failed lookup averages
        // 2.5 probes at a 50% load factor, but 8.5 probes at 75%
        if .capacity != 0 and .capacity - (.count + .deleted) > .capacity / 2 do
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
        let newCapacityBytes = reqCapacity * #sizeof(HashSetEntry'(K))

        if !.allocator do
            .allocator = @getcontext().allocator
        .table         = cast([*] HashSetEntry'(K)) Memory.alloc(newCapacityBytes, .allocator)
        let table = .tablePtr()

        // Be sure hash entry is 0
        Memory.clear(table, newCapacityBytes)

        // Copy the last me.table to the new me.table, removing me.deleted entries
        let oldCapacity = .capacity
        .capacity = reqCapacity
        let oldTablePtr = oldTable orelse cast([*] HashSetEntry'(K)) 1'u64
        for [i] in oldCapacity
        {
            let h = oldTablePtr[i].hash
            if h >= HashSet.HASH_FIRST
            {
                .emplaceInternal(h, &oldTablePtr[i].key)
            }
            elif h == HashSet.HASH_DELETED
            {
                @drop(&oldTablePtr[i].key)
            }
        }

        Memory.free(oldTable, oldCapacity * #sizeof(HashSetEntry'(K)), .allocator)
    }

    // Finds the correct index for a new key, handling collisions and me.deleted slots.
    // Uses linear probing to find the next available slot.
    //
    // Both loops test the cached hash first: an occupied slot that does not match is by far
    // the most frequent outcome, and it must cost a single compare. A set that has never seen
    // a removal takes the shorter loop, which has no deleted slot to remember.
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
                elif entryHash == HashSet.HASH_FREE do
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
            elif entryHash < HashSet.HASH_FIRST
            {
                if entryHash == HashSet.HASH_FREE do
                    return firstDeleted != Swag.U64.Max ? firstDeleted : index
                if firstDeleted == Swag.U64.Max do
                    firstDeleted = index
            }

            index = (index + 1) & mask
        }
    }

    // Adds a new key to the set. The key is copied; pass it with '#move' to move it instead.
    // If the key already exists, does nothing. Returns a pointer to the entry.
    #[Discardable]
    mtd add(key: #fwd K)->*HashSetEntry
    {
        .grow()

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashSet.HASH_FIRST do
            return table + index

        if table[index].hash == HashSet.HASH_FREE
        {
            table[index].key = #nodrop #fwd key
        }
        else
        {
            if table[index].hash == HashSet.HASH_DELETED do
                .deleted     -= 1
            table[index].key = #fwd key
        }

        table[index].hash = hashVal
        .count            += 1
        return table + index
    }

    // Internal helper to add a new element with a pre-computed hash.
    #[Discardable]
    mtd emplaceInternal(hashVal: u32, key: &K)->*HashSetEntry
        where Reflection.canCopy(#typeof(K))
    {
        .grow()

        var index = cast(u64) hashVal & (.capacity - 1)
        let table = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashSet.HASH_FIRST do
            return table + index

        if table[index].hash == HashSet.HASH_FREE
        {
            table[index].key = #relocate key
        }
        else
        {
            if table[index].hash == HashSet.HASH_DELETED do
                .deleted -= 1
            @drop(&table[index].key)
            table[index].key = #relocate key
        }

        table[index].hash = hashVal
        .count            += 1
        return table + index
    }

    // Toggles the presence of a key in the set.
    // The key is copied when inserted; pass it with '#move' to move it instead.
    // Returns 'true' if the key is present after the operation, or 'false' if it was removed.
    #[Discardable]
    public mtd toggleKey(key: #fwd K)->bool
    {
        .grow()

        let hashVal      = hashKey(key)
        let mask         = .capacity - 1
        var firstDeleted = Swag.U64.Max
        var index        = cast(u64) hashVal & mask
        let table        = .tablePtr()

        for
        {
            let entryHash = table[index].hash
            if entryHash == HashSet.HASH_FREE
            {
                let targetIndex = firstDeleted != Swag.U64.Max ? firstDeleted : index
                if table[targetIndex].hash == HashSet.HASH_FREE
                {
                    table[targetIndex].key = #nodrop #fwd key
                }
                else
                {
                    .deleted               -= 1
                    table[targetIndex].key = #fwd key
                }

                table[targetIndex].hash = hashVal
                .count                  += 1
                return true
            }

            if entryHash == HashSet.HASH_DELETED and firstDeleted == Swag.U64.Max
            {
                firstDeleted = index
            }
            elif entryHash == hashVal and table[index].key == key
            {
                table[index].hash = HashSet.HASH_DELETED
                .count            -= 1
                .deleted          += 1
                return false
            }

            index = (index + 1) & mask
        }
    }

    // Removes a key from the set.
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
                table[index].hash = HashSet.HASH_DELETED
                .count            -= 1
                .deleted          += 1
                return
            }

            index = (index + 1) & mask
        }
    }

    // Returns 'true' if the set contains the given key.
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

    // Removes all elements from the set without deallocating the me.table memory.
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
                if hashval >= HashSet.HASH_DELETED do
                    @drop(&table[i].key)

                if hashval == HashSet.HASH_DELETED do
                    .deleted -= 1
                elif hashval >= HashSet.HASH_FIRST do
                    .count    -= 1
                table[i].hash = HashSet.HASH_FREE

                // We are done if there's no more valid value, and no more me.deleted value
                if !.count and !.deleted do
                    break
            }
        }
    }
}

impl StrConv.IConvert for HashSet
{
    mtd const impl convert(buf: *ConcatBuffer, convFormat: StrConv.ConvertFormat, strFormat: #null string)
    {
        buf.addBytes("[")
        for k in me
        {
            if @index do
                buf.addBytes(", ")
            StrConv.convert'K(buf, k, convFormat, strFormat)
        }

        buf.addBytes("]")
    }
}
